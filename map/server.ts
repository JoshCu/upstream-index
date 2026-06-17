// server.ts
import map from "./index.html";

const dtiles = Bun.file("./tiles/divides.pmtiles");
const ftiles = Bun.file("./tiles/flowpaths.pmtiles");

Bun.serve({
  port: 3000,
  routes: {
    "/": map,
    "/divides.pmtiles": (req) => {
      const range = req.headers.get("range");
      const size = dtiles.size;
      if (!range) {
        return new Response(dtiles, { headers: { "Accept-Ranges": "bytes" } });
      }
      const [, s, e] = /bytes=(\d+)-(\d*)/.exec(range)!;
      const start = Number(s);
      const end = e ? Number(e) : size - 1;
      return new Response(dtiles.slice(start, end + 1), {
        status: 206,
        headers: {
          "Content-Range": `bytes ${start}-${end}/${size}`,
          "Accept-Ranges": "bytes",
          "Content-Length": String(end - start + 1),
          "Content-Type": "application/octet-stream",
        },
      });
    },
    "/flowpaths.pmtiles": (req) => {
      const range = req.headers.get("range");
      const size = ftiles.size;
      if (!range) {
        return new Response(ftiles, { headers: { "Accept-Ranges": "bytes" } });
      }
      const [, s, e] = /bytes=(\d+)-(\d*)/.exec(range)!;
      const start = Number(s);
      const end = e ? Number(e) : size - 1;
      return new Response(ftiles.slice(start, end + 1), {
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
