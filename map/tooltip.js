let state = {
  hoveredObject: null,
  hoverPosition: null,
  data: null,
  currentTimeIndex: 0,
};

export function handleHover(e) {
  const tooltip = document.getElementById("tooltip");
  const map = e.target;

  let cat = e.features[0];
  if (cat) {
    state.hoveredObject = {
      cat_id: "cat-" + cat.id,
      id: cat.properties.upstream_id,
      num_upstreams: cat.properties.num_upstreams,
    };
    state.hoverPosition = { x: e.point.x, y: e.point.y };

    map.getCanvas().style.cursor = "pointer";
    tooltip.classList.add("visible");
    tooltip.style.left = `${e.point.x + 15}px`;
    tooltip.style.top = `${e.point.y + 15}px`;

    updateTooltipContent(state.hoveredObject);
  } else {
    handleHoverLeave(e);
  }
}

export function handleHoverLeave(e) {
  const tooltip = document.getElementById("tooltip");
  state.hoveredObject = null;
  tooltip.classList.remove("visible");
  if (e?.target) {
    e.target.getCanvas().style.cursor = "";
  }
}

function updateTooltipContent(obj) {
  document.getElementById("tooltipTitle").textContent = obj.cat_id || "Unknown";
  document.getElementById("tooltip_upid").textContent =
    obj.id !== undefined ? obj.id : "N/A";
  document.getElementById("tooltip_num_upstreams").textContent =
    obj.num_upstreams !== undefined ? obj.num_upstreams : "N/A";
}
