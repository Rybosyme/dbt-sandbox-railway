-- One row per dated journal entry. An entry runs from its italic date line up to the next entry,
-- the chapter's footnotes, or the end of the chapter. A sidenote directly before an entry's date
-- line belongs to that entry.
with paragraphs as (
    select *
    from {{ ref('hoc_paragraphs') }}
    where paragraph_kind in ('text', 'sidenote')
),

header_dates as (
    select paragraph_id, entry_date as resolved_date, date_precision, resolution, weekday_matches
    from {{ ref('int_hoc__entry_dates') }}
),

grouped as (
    select
        *,
        count(*) filter (where is_journal_entry_start) over chapter_order
        + case
            when paragraph_kind = 'sidenote' and coalesce(lead(is_journal_entry_start) over chapter_order, false) then 1
            else 0
        end as entry_group
    from paragraphs
    window chapter_order as (partition by volume_number, chapter_seq order by volume_paragraph_seq)
),

entries as (
    select
        max(paragraph_id) filter (where is_journal_entry_start) as entry_id,
        max(chapter_id) as chapter_id,
        volume_number,
        min(volume_paragraph_seq) filter (where is_journal_entry_start) as volume_paragraph_seq,
        max(entry_date_text) as entry_date_text,
        string_agg(sidenote_text, ' / ' order by volume_paragraph_seq) as sidenotes,
        string_agg(clean_text, chr(10) || chr(10) order by volume_paragraph_seq)
            filter (where paragraph_kind = 'text') as entry_text,
        count(*) filter (where paragraph_kind = 'text') as paragraph_count,
        sum(word_count) filter (where paragraph_kind = 'text') as word_count,
        min(page_start) as page_start,
        max(page_end) as page_end
    from grouped
    where entry_group > 0
    group by volume_number, chapter_seq, entry_group
)

select
    e.entry_id,
    e.chapter_id,
    e.volume_number,
    e.volume_paragraph_seq,
    d.resolved_date as entry_date,
    d.date_precision,
    d.resolution as date_resolution,
    d.weekday_matches,
    e.entry_date_text,
    e.sidenotes,
    e.entry_text,
    e.paragraph_count,
    e.word_count,
    e.page_start,
    e.page_end
from entries as e
left join header_dates as d
    on d.paragraph_id = e.entry_id
