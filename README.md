# upstream-index
Using the [Nested Set Model](https://en.wikipedia.org/wiki/Nested_set_model) to index flowpaths.
This technique allows instant (O(1)) lookups for everything upstream of a given flowpath as well as guarenteeing upstream flowpaths are sorted sequentially.

## Use cases
* fast highlighting of upstream flowpaths on map interfaces, _*WITHOUT*_ needing any network traversal, connectivity, or graph information.
* guarenteing related data is split into _*at most*_ one more chunk than the minimum possible number of chunks required to store the data.

## Does this provide persistent ids that don't update when changes are made to the data?
Absolutely not! The same code run twice might even produce different results.
However, this doesn't matter for indexing.
The map tiles already need recreating when the underlying geometry changes so having to assign new id's is not a problem.
These should probably be used as an accompaniment to the current flowpath ids rather than replacing them.

### Map highlighting example
error handling has been removed to keep the example simple.
```javascript
map.on("click", "divides", (e) => {
  // get the first item clicked (catchments don't overlap so this should always be the correct item)
  const clicked_divide = e.features[0];
  // get the id saved in the map tile 
  selected_id = clicked_divide.properties.upstream_id;
  // get the number of upstream catchments saved in the map tile
  upstream_count = clicked_divide.properties.upstream_count;
  // set the pink map layer to highlight the clicked divide
  map.setFilter("selected-divides", ["==", "upstream_id", selected_id]);
  // set the orange map layer to highlight ALL upstream catchments, excluding the clicked divide
  map.setFilter("upstream-divides", [
    "all",
    [">", "upstream_id", selected_id],
    // sequential ids mean I can just add two numbers to get the range of upstream catchments
    ["<=", "upstream_id", selected_id + upstream_count],
    ["!=", "upstream_id", selected_id],
  ]);
});
```
