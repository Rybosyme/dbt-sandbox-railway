-- One row per History of the Church volume that has text loaded, with its chunks stitched back
-- into the full volume. Chunks always end on a paragraph break, so a blank line rejoins them.
with volumes as (
    select
        w.id as work_id,
        substring(w.title from 'Volume (\d+)$')::int as volume_number,
        w.title,
        ws.ebook_id
    from {{ source('library', 'work') }} as w
    left join {{ source('library', 'work_source') }} as ws
        on ws.work_id = w.id
        and ws.is_primary
    where w.title ilike 'History of the Church of Jesus Christ of Latter-day Saints, Volume %'
)

select
    v.work_id,
    v.volume_number,
    v.title,
    v.ebook_id,
    count(*) as chunk_count,
    string_agg(c.body, chr(10) || chr(10) order by c.chunk_no) as full_text
from volumes as v
inner join {{ source('library', 'work_chunk') }} as c
    on c.work_id = v.work_id
group by v.work_id, v.volume_number, v.title, v.ebook_id
