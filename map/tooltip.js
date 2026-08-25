let state = {
  hoveredObject: null,
  hoverPosition: null,
  data: null,
  currentTimeIndex: 0,
};

export function handleHover(e) {
  const tooltip = document.getElementById("tooltip");

  console.log(e);
  let cat = e.features[0];
  if (cat) {
    state.hoveredObject = {
      cat_id: "cat-" + cat.id,
      id: cat.properties.upstream_id,
      num_upstreams: cat.properties.num_upstreams,
    };
    state.hoverPosition = { x: e.x, y: e.y };

    tooltip.classList.add("visible");
    tooltip.style.left = `${e.x + 15}px`;
    tooltip.style.top = `${e.y + 15}px`;

    updateTooltipContent(state.hoveredObject);
  } else {
    state.hoveredObject = null;
    tooltip.classList.remove("visible");
  }
}

function updateTooltipContent(obj) {
  document.getElementById("tooltipTitle").textContent = obj.cat_id || "Unknown";
  document.getElementById("tooltip_upid").textContent =
    obj.id !== undefined ? obj.id : "N/A";
  document.getElementById("tooltip_num_upstreams").textContent =
    obj.num_upstreams !== undefined ? obj.num_upstreams : "N/A";
}
