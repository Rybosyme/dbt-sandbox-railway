-- One row per chapter, with its printed number and title, page range, size, the dates its
-- journal entries cover, and the full chapter text (footnotes and sidenotes left out).
with paragraphs as (
    select * from {{ ref('hoc_paragraphs') }}
),

chapters as (
    select
        chapter_id,
        work_id,
        volume_number,
        chapter_seq,
        max(clean_text) filter (where paragraph_kind = 'chapter_heading') as chapter_label,
        max(substring(upper(clean_text) from '^CHAPTER\s+([IVXL]+)'))
            filter (where paragraph_kind = 'chapter_heading') as chapter_numeral,
        max(clean_text) filter (where paragraph_kind = 'chapter_title') as chapter_title,
        min(page_start) as page_start,
        max(page_end) as page_end,
        count(*) filter (where paragraph_kind = 'text') as text_paragraph_count,
        count(*) filter (where paragraph_kind = 'sidenote') as sidenote_count,
        count(*) filter (where paragraph_kind = 'footnote') as footnote_paragraph_count,
        count(*) filter (where is_journal_entry_start) as journal_entry_count,
        coalesce(sum(word_count) filter (where paragraph_kind = 'text'), 0) as word_count,
        string_agg(clean_text, chr(10) || chr(10) order by volume_paragraph_seq)
            filter (where paragraph_kind = 'text') as chapter_text
    from paragraphs
    group by chapter_id, work_id, volume_number, chapter_seq
),

entry_dates as (
    select
        chapter_id,
        min(entry_date) as first_entry_date,
        max(entry_date) as last_entry_date
    from {{ ref('hoc_timeline') }}
    group by chapter_id
)

select
    c.chapter_id,
    c.work_id,
    c.volume_number,
    c.chapter_seq,
    c.chapter_label,
    {{ roman_to_int('c.chapter_numeral') }} as printed_chapter_number,
    c.chapter_title,
    c.page_start,
    c.page_end,
    d.first_entry_date,
    d.last_entry_date,
    c.text_paragraph_count,
    c.sidenote_count,
    c.footnote_paragraph_count,
    c.journal_entry_count,
    c.word_count,
    c.chapter_text
from chapters as c
left join entry_dates as d
    on d.chapter_id = c.chapter_id
