#!/usr/bin/env -S deno run --allow-read --allow-write --allow-env --allow-net --allow-ffi --allow-sys
/**
 * ECharts PNG Renderer (Deno + SSR Mode + resvg-js)
 *
 * Uses ECharts official SSR mode (5.3.0+) for clean server-side rendering.
 * No DOM or canvas dependencies - generates SVG string directly.
 * Uses @resvg/resvg-js for SVG to PNG conversion.
 *
 * Usage:
 *   deno run --allow-read --allow-write --allow-ffi echarts-render.ts <config.json> <output.png> [width] [height]
 *
 * Arguments:
 *   config.json - Path to ECharts config JSON file
 *   output.png  - Path for output PNG file
 *   width       - Chart width in pixels (default: 600)
 *   height      - Chart height in pixels (default: 400)
 */

import * as echarts from "npm:echarts@5.5.1";
import { dirname } from "jsr:@std/path@1";
import { ensureDir } from "jsr:@std/fs@1";

function patchProcessReportForSandbox(): void {
  const proc = (globalThis as { process?: unknown }).process as
    | { report?: { getReport?: () => unknown } }
    | undefined;

  if (!proc || !proc.report || typeof proc.report.getReport !== "function") {
    return;
  }

  const report = proc.report;
  const original = report.getReport.bind(report);
  report.getReport = (): unknown => {
    try {
      return original();
    } catch {
      // Some sandboxed environments block Node's report internals (used by resvg-js isMusl probe).
      return { header: { glibcVersionRuntime: "2.31" } };
    }
  };
}

patchProcessReportForSandbox();

let Resvg: typeof import("npm:@resvg/resvg-js@2.6.2").Resvg;
try {
  const mod = await import("npm:@resvg/resvg-js@2.6.2");
  Resvg = mod.Resvg;
} catch (err) {
  console.error(`Error loading resvg-js: ${(err as Error).message}`);
  Deno.exit(1);
}

// Show help
if (Deno.args.includes("--help") || Deno.args.includes("-h")) {
  console.log(`
ECharts PNG Renderer (Deno SSR Mode + resvg-js)

Usage:
  deno run --allow-read --allow-write --allow-ffi echarts-render.ts <config.json> <output.png> [width] [height]

Arguments:
  config.json - Path to ECharts config JSON file
  output.png  - Path for output PNG file
  width       - Chart width in pixels (default: 600)
  height      - Chart height in pixels (default: 400)

Example:
  deno run --allow-read --allow-write --allow-ffi echarts-render.ts chart.json output.png 800 600
`);
  Deno.exit(0);
}

// Parse arguments
const args = Deno.args;
if (args.length < 2) {
  console.error("Error: Missing required arguments");
  console.error(
    "Usage: deno run --allow-read --allow-write echarts-render.ts <config.json> <output.png> [width] [height]"
  );
  Deno.exit(1);
}

const configPath = args[0];
const outputPath = args[1];
const width = parseInt(args[2]) || 600;
const height = parseInt(args[3]) || 400;

// Read config file
let chartConfig: Record<string, unknown>;
try {
  const configContent = await Deno.readTextFile(configPath);
  chartConfig = JSON.parse(configContent);
} catch (err) {
  console.error(`Error reading config file: ${(err as Error).message}`);
  Deno.exit(1);
}

// Check if chart has data - if dataset is empty and series uses encode, skip
function hasData(config: Record<string, unknown>): boolean {
  const dataset = config.dataset as Record<string, unknown> | undefined;
  const series = config.series as Array<Record<string, unknown>> | undefined;

  // If no series, can't render
  if (!series || series.length === 0) return false;

  // Check if any series uses encode (requires dataset)
  const usesEncode = series.some(s => s.encode !== undefined);

  // If uses encode but dataset is empty/missing, no data
  if (usesEncode) {
    if (!dataset) return false;
    const source = dataset.source as unknown[] | undefined;
    if (!source || source.length === 0) {
      // Check for inline data in series
      const hasInlineData = series.some(s => s.data !== undefined);
      return hasInlineData;
    }
  }

  return true;
}

// Chart types with known SSR issues - need special handling
const SSR_PROBLEMATIC_TYPES = ["sankey", "graph", "tree", "treemap"];

// Prepare config for SSR rendering - disable animations and interactive features
// that cause issues with certain chart types in SSR mode
function prepareForSSR(config: Record<string, unknown>): Record<string, unknown> {
  const prepared = { ...config };
  const series = prepared.series as Array<Record<string, unknown>> | undefined;

  // Detect if any series uses problematic chart types
  const hasProblematicType = series?.some(s =>
    SSR_PROBLEMATIC_TYPES.includes(String(s.type).toLowerCase())
  );

  if (hasProblematicType) {
    // Disable animation globally - this is the main fix for CHANGABLE_METHODS error
    prepared.animation = false;

    // Disable emphasis effects that can cause issues
    if (series) {
      prepared.series = series.map(s => ({
        ...s,
        animation: false,
        // Disable emphasis for sankey/graph
        emphasis: s.emphasis ? { ...s.emphasis as object, disabled: true } : { disabled: true },
        // Simplify line styles for sankey
        ...(s.type === "sankey" && s.lineStyle ? {
          lineStyle: {
            ...(s.lineStyle as object),
            opacity: (s.lineStyle as Record<string, unknown>).opacity ?? 0.4
          }
        } : {})
      }));
    }
  }

  return prepared;
}

if (!hasData(chartConfig)) {
  console.error("Error rendering chart: Chart has no data (empty dataset with encode series)");
  Deno.exit(1);
}

// Main render function
async function renderChart() {
  try {
    // Prepare config for SSR (disable animations for problematic chart types)
    const ssrConfig = prepareForSSR(chartConfig);

    // Initialize ECharts in SSR mode (no DOM required)
    // Official API: https://apache.github.io/echarts-handbook/en/how-to/cross-platform/server/
    const chart = echarts.init(null, null, {
      renderer: "svg",
      ssr: true,
      width: width,
      height: height,
    });

    // Set chart options
    chart.setOption(ssrConfig);

    // Render to SVG string (official SSR API)
    const svgString = chart.renderToSVGString();

    // Cleanup
    chart.dispose();

    // Ensure output directory exists
    const outputDir = dirname(outputPath);
    if (outputDir && outputDir !== ".") {
      await ensureDir(outputDir);
    }

    // Convert SVG to PNG using resvg-js
    const resvg = new Resvg(svgString, {
      fitTo: {
        mode: "width",
        value: width,
      },
    });

    const pngData = resvg.render();
    const pngBuffer = pngData.asPng();

    // Write PNG file
    await Deno.writeFile(outputPath, pngBuffer);

    console.log(`Chart rendered: ${outputPath}`);
  } catch (err) {
    console.error(`Error rendering chart: ${(err as Error).message}`);
    Deno.exit(1);
  }
}

// Run
try {
  await renderChart();
  Deno.exit(0);
} catch (err) {
  console.error(`Unexpected error: ${(err as Error).message}`);
  Deno.exit(1);
}
