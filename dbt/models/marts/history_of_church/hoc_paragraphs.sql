-- One row per paragraph in the body of each History of the Church volume, from each chapter
-- heading through that chapter's footnotes. Title pages, the table of contents, the editor's
-- introduction, and the index are left out.
with split as (
    select
        v.work_id,
        v.volume_number,
        p.split_seq,
        regexp_replace(p.raw_text, '\s+$', '') as raw_text
    from {{ ref('stg_library__hoc_volumes') }} as v
    cross join lateral regexp_split_to_table(v.full_text, '\n(?:[ \t]*\n)+')
        with ordinality as p (raw_text, split_seq)
),

numbered as (
    select
        work_id,
        volume_number,
        row_number() over (partition by volume_number order by split_seq) as volume_paragraph_seq,
        raw_text,
        -- {123} (or {XIV} in the front matter) marks where a printed page starts.
        regexp_replace(regexp_replace(raw_text, '\{\w+\}', '', 'g'), '^\s+|\s+$', '', 'g') as unmarked_text,
        (regexp_match(raw_text, '^\s*\{(\d+)\}'))[1]::int as leading_page_marker,
        (regexp_match(raw_text, '.*\{(\d+)\}'))[1]::int as last_page_marker
    from split
    where raw_text ~ '\S'
),

page_groups as (
    select
        *,
        count(last_page_marker) over (partition by volume_number order by volume_paragraph_seq) as page_group
    from numbered
),

paged as (
    select
        *,
        max(last_page_marker) over (partition by volume_number, page_group) as page_end
    from page_groups
),

paged_with_start as (
    select
        *,
        coalesce(
            leading_page_marker,
            lag(page_end) over (partition by volume_number order by volume_paragraph_seq)
        ) as page_start
    from paged
),

-- The table of contents repeats every chapter heading, so the body starts at the last "Chapter I."
body_starts as (
    select
        volume_number,
        max(volume_paragraph_seq) as body_start_seq
    from numbered
    where unmarked_text ~* '^chapter\s+i\.?$'
    group by volume_number
),

body_bounds as (
    select
        s.volume_number,
        s.body_start_seq,
        min(n.volume_paragraph_seq) filter (where n.unmarked_text ~* '^index to vol') as index_start_seq
    from body_starts as s
    left join numbered as n
        on n.volume_number = s.volume_number
        and n.volume_paragraph_seq > s.body_start_seq
    group by s.volume_number, s.body_start_seq
),

body as (
    select p.*
    from paged_with_start as p
    inner join body_bounds as b
        on b.volume_number = p.volume_number
    where p.volume_paragraph_seq >= b.body_start_seq
        and (b.index_start_seq is null or p.volume_paragraph_seq < b.index_start_seq)
        and p.unmarked_text <> ''
        and p.unmarked_text !~* '^end of vol'
),

classified as (
    select
        *,
        upper((regexp_match(unmarked_text, '^chapter\s+([ivxl]+)\y[^a-z]*$', 'i'))[1]) as chapter_numeral,
        unmarked_text ~* '^footnotes?[:.]?$' as is_footnote_heading,
        regexp_replace((regexp_match(unmarked_text, '^\[Sidenote:\s*([^]]*)\]$'))[1], '\s+', ' ', 'g') as sidenote_text,
        -- Journal entries open with an italic date, e.g. "_Tuesday, June 17_.--" or "_Wednesday, 8_.--".
        regexp_replace(
            (regexp_match(
                unmarked_text,
                '^_((?:Sunday|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|{{ hoc_month_pattern() }})[^_]{0,60})_'
            ))[1],
            '[\s.,:;-]+$', ''
        ) as italic_date_text
    from body
),

chaptered as (
    select
        *,
        count(chapter_numeral) over (partition by volume_number order by volume_paragraph_seq) as chapter_seq
    from classified
),

positioned as (
    select
        *,
        row_number() over chapter_window as chapter_paragraph_seq,
        count(*) filter (where is_footnote_heading) over chapter_window as footnote_headings_so_far,
        count(sidenote_text) over chapter_window as sidenote_group
    from chaptered
    window chapter_window as (partition by volume_number, chapter_seq order by volume_paragraph_seq)
),

kinds as (
    select
        *,
        case
            when chapter_numeral is not null then 'chapter_heading'
            when chapter_paragraph_seq = 2 then 'chapter_title'
            when is_footnote_heading then 'footnote_heading'
            when footnote_headings_so_far > 0 then 'footnote'
            when sidenote_text is not null then 'sidenote'
            else 'text'
        end as paragraph_kind
    from positioned
)

select
    format('v%s-p%s', volume_number, lpad(volume_paragraph_seq::text, 5, '0')) as paragraph_id,
    format('v%s-c%s', volume_number, lpad(chapter_seq::text, 2, '0')) as chapter_id,
    work_id,
    volume_number,
    chapter_seq,
    chapter_paragraph_seq,
    volume_paragraph_seq,
    paragraph_kind,
    coalesce(paragraph_kind = 'text' and italic_date_text ~ '\d', false) as is_journal_entry_start,
    case when paragraph_kind = 'text' and italic_date_text ~ '\d' then italic_date_text end as entry_date_text,
    sidenote_text,
    case
        when paragraph_kind in ('text', 'sidenote')
            then max(sidenote_text) over (partition by volume_number, chapter_seq, sidenote_group)
    end as current_sidenote,
    -- Pages before the first page marker in a volume's body are page 1.
    coalesce(page_start, 1) as page_start,
    coalesce(page_end, 1) as page_end,
    raw_text ~ '^\s{3,}' as is_indented,
    raw_text,
    case
        when sidenote_text is not null then sidenote_text
        else regexp_replace(replace(unmarked_text, '_', ''), '\s+', ' ', 'g')
    end as clean_text,
    array_length(regexp_split_to_array(
        case
            when sidenote_text is not null then sidenote_text
            else regexp_replace(replace(unmarked_text, '_', ''), '\s+', ' ', 'g')
        end,
        '\s+'
    ), 1) as word_count
from kinds
