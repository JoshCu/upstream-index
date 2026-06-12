// server.ts
import map from "./map.html";

const tiles = Bun.file("./conus.pmtiles");

Bun.serve({
  port: 3000,
  routes: {
    "/": map,
    "/conus.pmtiles": (req) => {
      const range = req.headers.get("range");
      const size = tiles.size;
      if (!range) {
        return new Response(tiles, { headers: { "Accept-Ranges": "bytes" } });
      }
      const [, s, e] = /bytes=(\d+)-(\d*)/.exec(range)!;
      const start = Number(s);
      const end = e ? Number(e) : size - 1;
      return new Response(tiles.slice(start, end + 1), {
        status: 206,
        headers: {
          "Content-Range": `bytes ${start}-${end}/${size}`,
          "Accept-Ranges": "bytes",
          "Content-Length": String(end - start + 1),
          "Content-Type": "application/octet-stream",
        },
      });
    },
  },
});

console.log("http://localhost:3000");
