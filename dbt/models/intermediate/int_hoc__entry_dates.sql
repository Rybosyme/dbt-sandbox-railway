{{ config(materialized='table') }}

-- The calendar date of each History of the Church journal entry. Entries are resolved one after
-- another in reading order: whatever a date line leaves out is filled in from the previous entry's
-- date, preferring the weekday the line names. Until a volume's first entry resolves, the latest
-- full date written in the text (a dated letter, minutes) stands in for the previous entry.
with recursive entries as (
    select
        paragraph_id,
        chapter_id,
        volume_number,
        volume_paragraph_seq,
        entry_date_text,
        row_number() over (partition by volume_number order by volume_paragraph_seq) as entry_seq,
        {{ hoc_weekday('entry_date_text') }} as weekday_text,
        {{ hoc_year('entry_date_text') }} as year_explicit,
        {{ hoc_month_number('entry_date_text') }} as month_explicit,
        {{ hoc_day('entry_date_text') }} as day_explicit
    from {{ ref('hoc_paragraphs') }}
    where is_journal_entry_start
),

written_dates as materialized (
    select
        p.volume_number,
        p.volume_paragraph_seq,
        {{ safe_make_date(hoc_year('m.captures[1]'), hoc_month_number('m.captures[1]'), hoc_day('m.captures[1]')) }} as written_date
    from {{ ref('hoc_paragraphs') }} as p
    cross join lateral regexp_matches(p.clean_text, '{{ hoc_date_pattern() }}', 'g') as m (captures)
    where p.paragraph_kind = 'text'
),

entries_with_fallback as materialized (
    select
        e.*,
        (
            select w.written_date
            from written_dates as w
            where w.volume_number = e.volume_number
                and w.volume_paragraph_seq <= e.volume_paragraph_seq
                and w.written_date is not null
            order by w.volume_paragraph_seq desc
            limit 1
        ) as fallback_date
    from entries as e
),

resolved (paragraph_id, volume_number, entry_seq, context_date, entry_date) as (
    select
        e.paragraph_id,
        e.volume_number,
        e.entry_seq,
        e.fallback_date,
        {{ hoc_resolve_date('e.year_explicit', 'e.month_explicit', 'e.day_explicit', 'e.weekday_text', 'e.fallback_date') }}
    from entries_with_fallback as e
    where e.entry_seq = 1

    union all

    select
        e.paragraph_id,
        e.volume_number,
        e.entry_seq,
        coalesce(r.entry_date, r.context_date, e.fallback_date),
        {{ hoc_resolve_date(
            'e.year_explicit', 'e.month_explicit', 'e.day_explicit', 'e.weekday_text',
            'coalesce(r.entry_date, r.context_date, e.fallback_date)'
        ) }}
    from resolved as r
    inner join entries_with_fallback as e
        on e.volume_number = r.volume_number
        and e.entry_seq = r.entry_seq + 1
),

dated as (
    select
        e.*,
        r.context_date,
        -- A date line with a month and year but no day ("January, 1835") gets the first of the month.
        coalesce(r.entry_date, make_date(e.year_explicit, e.month_explicit, 1)) as entry_date,
        case
            when r.entry_date is not null then 'day'
            when e.year_explicit is not null and e.month_explicit is not null then 'month'
        end as date_precision
    from entries_with_fallback as e
    inner join resolved as r
        on r.paragraph_id = e.paragraph_id
)

select
    paragraph_id,
    chapter_id,
    volume_number,
    volume_paragraph_seq,
    entry_seq,
    entry_date_text,
    weekday_text,
    year_explicit,
    month_explicit,
    day_explicit,
    entry_date,
    date_precision,
    case
        when entry_date is null then 'unresolved'
        when year_explicit is not null and month_explicit is not null then 'explicit'
        when month_explicit is not null then 'inferred_year'
        else 'inferred_month_and_year'
    end as resolution,
    case
        when weekday_text is not null and date_precision = 'day'
            then to_char(entry_date, 'FMDay') = weekday_text
    end as weekday_matches,
    context_date
from dated
