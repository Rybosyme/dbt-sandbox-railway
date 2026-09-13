-- One row per date written in the body text: full dates ("June 28th, 1840", "2nd January, 1843"),
-- partial dates ("June 17", "Wednesday, 8th"), and month-year references ("April, 1830").
-- Partial dates get their month and year from the journal entry they appear in (or follow).
with paragraphs as (
    select
        paragraph_id,
        chapter_id,
        volume_number,
        volume_paragraph_seq,
        paragraph_kind,
        is_journal_entry_start,
        clean_text
    from {{ ref('hoc_paragraphs') }}
    where paragraph_kind in ('chapter_title', 'text', 'sidenote', 'footnote')
),

entry_dates as (
    select * from {{ ref('int_hoc__entry_dates') }}
),

matches as (
    select
        p.*,
        m.mention_seq,
        m.captures[1] as mention_text
    from paragraphs as p
    cross join lateral regexp_matches(p.clean_text, '{{ hoc_date_pattern() }}', 'g')
        with ordinality as m (captures, mention_seq)
),

parsed as (
    select
        paragraph_id,
        chapter_id,
        volume_number,
        volume_paragraph_seq,
        paragraph_kind,
        mention_seq,
        mention_text,
        is_journal_entry_start and mention_seq = 1 and starts_with(clean_text, mention_text) as is_entry_header,
        {{ hoc_weekday('mention_text') }} as weekday_text,
        {{ hoc_year('mention_text') }} as year_explicit,
        {{ hoc_month_number('mention_text') }} as month_explicit,
        {{ hoc_day('mention_text') }} as day_explicit
    from matches
),

mentions as (
    select *
    from parsed
    where day_explicit is null or day_explicit between 1 and 31
),

written_dates as materialized (
    select
        volume_number,
        volume_paragraph_seq,
        {{ safe_make_date('year_explicit', 'month_explicit', 'day_explicit') }} as written_date
    from mentions
    where paragraph_kind = 'text'
),

-- A paragraph's context is the latest dated journal entry at or before it, or failing that the
-- latest full date written in the text.
mention_paragraphs as (
    select distinct paragraph_id, volume_number, volume_paragraph_seq
    from mentions
),

context as (
    select
        p.paragraph_id,
        e.paragraph_id as context_paragraph_id,
        coalesce(
            e.entry_date,
            (
                select w.written_date
                from written_dates as w
                where w.volume_number = p.volume_number
                    and w.volume_paragraph_seq <= p.volume_paragraph_seq
                    and w.written_date is not null
                order by w.volume_paragraph_seq desc
                limit 1
            )
        ) as context_date
    from mention_paragraphs as p
    left join lateral (
        select ed.paragraph_id, ed.entry_date
        from entry_dates as ed
        where ed.volume_number = p.volume_number
            and ed.volume_paragraph_seq <= p.volume_paragraph_seq
            and ed.entry_date is not null
        order by ed.volume_paragraph_seq desc
        limit 1
    ) as e on true
),

resolved as (
    select
        m.*,
        c.context_paragraph_id,
        c.context_date,
        hd.entry_date as header_entry_date,
        hd.date_precision as header_date_precision,
        hd.resolution as header_resolution,
        hd.weekday_matches as header_weekday_matches,
        case
            when hd.entry_date is not null
                then hd.entry_date
            when m.year_explicit is not null and m.month_explicit is not null and m.day_explicit is null
                then make_date(m.year_explicit, m.month_explicit, 1)
            -- Footnotes are the editor's notes, so the surrounding journal dates say nothing about them.
            when m.paragraph_kind = 'footnote' and (m.year_explicit is null or m.month_explicit is null)
                then null
            else {{ hoc_resolve_date('m.year_explicit', 'm.month_explicit', 'm.day_explicit', 'm.weekday_text', 'c.context_date') }}
        end as resolved_date
    from mentions as m
    left join context as c
        on c.paragraph_id = m.paragraph_id
    left join entry_dates as hd
        on hd.paragraph_id = m.paragraph_id
        and m.is_entry_header
)

select
    paragraph_id || '-m' || mention_seq as mention_id,
    paragraph_id,
    chapter_id,
    volume_number,
    volume_paragraph_seq,
    mention_seq,
    mention_text,
    paragraph_kind,
    is_entry_header,
    weekday_text,
    year_explicit,
    month_explicit,
    day_explicit,
    resolved_date,
    case
        when resolved_date is null then null
        when header_entry_date is not null then header_date_precision
        when day_explicit is null then 'month'
        else 'day'
    end as date_precision,
    case
        when resolved_date is null then 'unresolved'
        when header_entry_date is not null then header_resolution
        when year_explicit is not null and month_explicit is not null then 'explicit'
        when month_explicit is not null then 'inferred_year'
        else 'inferred_month_and_year'
    end as resolution,
    case
        when header_entry_date is not null then header_weekday_matches
        when weekday_text is not null and day_explicit is not null and resolved_date is not null
            then to_char(resolved_date, 'FMDay') = weekday_text
    end as weekday_matches,
    context_paragraph_id,
    context_date
from resolved
