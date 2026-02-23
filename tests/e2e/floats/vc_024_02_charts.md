# Chart Generation Test @SPEC-FLOAT-005

## Inline Data Chart

```chart:bar-chart{caption="Sales by Region"}
{
  "xAxis": {
    "type": "category",
    "data": ["North", "South", "East", "West"]
  },
  "yAxis": {
    "type": "value"
  },
  "series": [{
    "type": "bar",
    "data": [120, 200, 150, 80]
  }]
}
```

## Pie Chart

```chart:pie-chart{caption="Market Share Distribution"}
{
  "series": [{
    "type": "pie",
    "radius": "50%",
    "data": [
      {"value": 335, "name": "Product A"},
      {"value": 310, "name": "Product B"},
      {"value": 234, "name": "Product C"},
      {"value": 135, "name": "Product D"}
    ]
  }]
}
```

## Reference

See [chart:bar-chart](#) for regional sales.
See [chart:pie-chart](#) for market distribution.
