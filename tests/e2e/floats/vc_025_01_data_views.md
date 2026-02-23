# Data View Injection Test @SPEC-FLOAT-007

Exercises data-loader behavior through markdown chart blocks.

## Parameter Parsing And Dataset Injection

```chart:dl-params{caption="DL params" view="test_fixtures.params_echo" model="default" count=7 params="alpha=3.5,name=delta" spec_id="DL-SPEC"}
{
  "title": { "text": "DL_CASE_PARAMS" },
  "dataset": { "source": [["kind", "value"], ["ORIGINAL", 1]] },
  "xAxis": { "type": "category" },
  "yAxis": { "type": "value" },
  "series": [{ "type": "bar" }]
}
```

## Default Model Fallback

```chart:dl-fallback{caption="DL fallback" view="gauss" model="sw_docs" params="mean=0,sigma=1,xmin=-1,xmax=1,points=5"}
{
  "title": { "text": "DL_CASE_FALLBACK" },
  "dataset": { "source": [["kind", "value"], ["ORIGINAL", 1]] },
  "xAxis": { "type": "value" },
  "yAxis": { "type": "value" },
  "series": [{ "type": "line", "smooth": true }]
}
```

## Missing View Module (Config Preserved)

```chart:dl-missing{caption="DL missing view" view="missing_view" model="sw_docs"}
{
  "title": { "text": "DL_CASE_MISSING" },
  "dataset": { "source": [["kind", "value"], ["ORIGINAL", 1]] },
  "xAxis": { "type": "category" },
  "yAxis": { "type": "value" },
  "series": [{ "type": "bar" }]
}
```

## Invalid Generate Export (Config Preserved)

```chart:dl-nonfunc{caption="DL invalid generate" view="test_fixtures.bad_nonfunc" model="default"}
{
  "title": { "text": "DL_CASE_NONFUNC" },
  "dataset": { "source": [["kind", "value"], ["ORIGINAL", 1]] },
  "xAxis": { "type": "category" },
  "yAxis": { "type": "value" },
  "series": [{ "type": "bar" }]
}
```

## Generate Runtime Failure (Config Preserved)

```chart:dl-throw{caption="DL throw" view="test_fixtures.bad_throw" model="default"}
{
  "title": { "text": "DL_CASE_THROW" },
  "dataset": { "source": [["kind", "value"], ["ORIGINAL", 1]] },
  "xAxis": { "type": "category" },
  "yAxis": { "type": "value" },
  "series": [{ "type": "bar" }]
}
```

## Unknown View Result Format (Config Preserved)

```chart:dl-unknown{caption="DL unknown format" view="test_fixtures.bad_return" model="default"}
{
  "title": { "text": "DL_CASE_UNKNOWN" },
  "dataset": { "source": [["kind", "value"], ["ORIGINAL", 1]] },
  "xAxis": { "type": "category" },
  "yAxis": { "type": "value" },
  "series": [{ "type": "bar" }]
}
```

## Sankey Injection Path

```chart:dl-sankey{caption="DL sankey" view="test_fixtures.sankey_edges" model="default" value=4}
{
  "title": { "text": "DL_CASE_SANKEY" },
  "dataset": { "source": [["kind", "value"], ["ORIGINAL", 1]] },
  "series": [{ "type": "sankey", "data": [], "links": [] }]
}
```

## No View (No Injection)

```chart:dl-noview{caption="DL no view"}
{
  "title": { "text": "DL_CASE_NOVIEW" },
  "dataset": { "source": [["kind", "value"], ["ORIGINAL", 1]] },
  "xAxis": { "type": "category" },
  "yAxis": { "type": "value" },
  "series": [{ "type": "bar" }]
}
```
