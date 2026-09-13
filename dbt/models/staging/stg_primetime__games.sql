-- Example staging model. Delete or replace it once you have your own.
select *
from {{ source('primetime', 'games') }}
