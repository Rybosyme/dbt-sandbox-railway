{# Regex (Postgres ARE syntax) matching a month name or its common abbreviation. #}
{% macro hoc_month_pattern() -%}
(?:January|February|March|April|May|June|July|August|September|October|November|December|Jan\.|Feb\.|Mar\.|Apr\.|Aug\.|Sept?\.|Oct\.|Nov\.|Dec\.)
{%- endmacro %}


{# Regex with one capture group matching a written date: "June 28th, 1840", "the 2nd of January, 1843",
   "Wednesday, 8th", "Sunday Morning, July 17, 1842", or "April, 1830". #}
{% macro hoc_date_pattern() -%}
    {%- set weekday -%}(?:Sunday|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday){%- endset -%}
    {%- set weekday_prefix -%}(?:{{ weekday }}(?:\s+(?:[Mm]orning|[Aa]fternoon|[Ee]vening|[Nn]ight))?,?\s+)?{%- endset -%}
    {%- set month = hoc_month_pattern() -%}
    {%- set day -%}\y\d{1,2}(?:st|nd|rd|th|d)?\y{%- endset -%}
    {%- set year -%}\y1[5-9]\d\d\y{%- endset -%}
    ({{ weekday_prefix }}(?:{{ month }},?\s+{{ day }}(?:,?\s+{{ year }})?|(?:the\s+)?{{ day }}\s+(?:day\s+)?(?:of\s+)?{{ month }}(?:,?\s+{{ year }})?)|{{ weekday }},?\s+(?:the\s+)?{{ day }}|{{ month }},?\s+{{ year }})
{%- endmacro %}


{# The parts of a date written in a piece of text: the first weekday, four-digit year, month, and day number. #}
{% macro hoc_weekday(expression) -%}
substring({{ expression }} from '(Sunday|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday)')
{%- endmacro %}

{% macro hoc_year(expression) -%}
substring({{ expression }} from '\y(1[5-9]\d\d)\y')::int
{%- endmacro %}

{% macro hoc_month_number(expression) -%}
case lower(left(substring({{ expression }} from '({{ hoc_month_pattern() }})'), 3))
    when 'jan' then 1 when 'feb' then 2 when 'mar' then 3 when 'apr' then 4
    when 'may' then 5 when 'jun' then 6 when 'jul' then 7 when 'aug' then 8
    when 'sep' then 9 when 'oct' then 10 when 'nov' then 11 when 'dec' then 12
end
{%- endmacro %}

{% macro hoc_day(expression) -%}
substring(regexp_replace({{ expression }}, '\y1[5-9]\d\d\y', '', 'g') from '\y(\d{1,2})(?:st|nd|rd|th|d)?\y')::int
{%- endmacro %}


{# make_date() that returns null instead of raising for impossible dates such as February 30. #}
{% macro safe_make_date(year, month, day) -%}
case
    when ({{ year }}) is not null
        and ({{ month }}) between 1 and 12
        and ({{ day }}) between 1 and 31
        and ({{ day }}) <= extract(day from make_date(({{ year }})::int, ({{ month }})::int, 1) + interval '1 month' - interval '1 day')
        then make_date(({{ year }})::int, ({{ month }})::int, ({{ day }})::int)
end
{%- endmacro %}


{# Fills in a partial date from a nearby known date. With a written month, the candidates are that
   month a year either side of the context date; without one, the month before, of, and after it.
   Candidates within 90 days of the context win, then those on the written weekday, then the
   nearest. The 90-day tier stops a mistyped weekday from moving a date into another year. #}
{% macro hoc_resolve_date(year, month, day, weekday, context_date) -%}
case
    when ({{ year }}) is not null and ({{ month }}) is not null
        then {{ safe_make_date(year, month, day) }}
    else (
        select candidate.d
        from (
            select
                {{ safe_make_date('extract(year from s.month_start)', 'extract(month from s.month_start)', day) }} as d
            from generate_series(
                date_trunc('month', ({{ context_date }})::timestamp) - interval '13 months',
                date_trunc('month', ({{ context_date }})::timestamp) + interval '13 months',
                interval '1 month'
            ) as s (month_start)
            where (({{ year }}) is null or extract(year from s.month_start) = ({{ year }}))
                and (
                    extract(month from s.month_start) = ({{ month }})
                    or (
                        ({{ month }}) is null
                        and s.month_start between date_trunc('month', ({{ context_date }})::timestamp) - interval '1 month'
                            and date_trunc('month', ({{ context_date }})::timestamp) + interval '1 month'
                    )
                )
        ) as candidate
        where candidate.d is not null
        order by
            abs(candidate.d - ({{ context_date }})) <= 90 desc,
            coalesce(to_char(candidate.d, 'FMDay') = ({{ weekday }}), false) desc,
            abs(candidate.d - ({{ context_date }})),
            candidate.d desc
        limit 1
    )
end
{%- endmacro %}


{# Converts an upper-case Roman numeral column to an integer (1 to max_value). #}
{% macro roman_to_int(expression, max_value=60) -%}
    {%- set numerals = [(50, 'L'), (40, 'XL'), (10, 'X'), (9, 'IX'), (5, 'V'), (4, 'IV'), (1, 'I')] -%}
    case {{ expression }}
    {%- for n in range(1, max_value + 1) %}
        {%- set ns = namespace(remaining=n, roman='') %}
        {%- for pair in numerals %}
            {%- for _ in range(ns.remaining // pair[0]) %}{% set ns.roman = ns.roman ~ pair[1] %}{% endfor %}
            {%- set ns.remaining = ns.remaining % pair[0] %}
        {%- endfor %}
        when '{{ ns.roman }}' then {{ n }}
    {%- endfor %}
    end
{%- endmacro %}
