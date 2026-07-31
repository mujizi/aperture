import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import type { Request, Response } from "express";
import { z } from "zod";
import type { EventStore } from "./store.js";
import { REVIEW_WIDGET_URI, reviewWidgetHtml } from "./widget.js";

function asToolResult(review: Awaited<ReturnType<EventStore["latestReview"]>>) {
  return {
    structuredContent: { review },
    content: [
      {
        type: "text" as const,
        text: JSON.stringify({
          review,
          instruction: review
            ? "Present resultMarkdown directly without adding another summary."
            : "No Aperture review exists yet."
        })
      }
    ]
  };
}

function createApertureMcpServer(store: EventStore) {
  const server = new McpServer({
    name: "aperture-attention",
    version: "0.1.0"
  });

  server.registerResource(
    "aperture-review-widget",
    REVIEW_WIDGET_URI,
    {
      title: "Aperture Attention Review",
      description: "Interactive 30-second review for the latest agent turn",
      mimeType: "text/html;profile=mcp-app"
    },
    async () => ({
      contents: [
        {
          uri: REVIEW_WIDGET_URI,
          mimeType: "text/html;profile=mcp-app",
          text: reviewWidgetHtml,
          _meta: {
            ui: { prefersBorder: false },
            "openai/widgetPrefersBorder": false,
            "openai/widgetDescription": "Aperture attention routing review"
          }
        }
      ]
    })
  );

  server.registerTool(
    "aperture_get_review",
    {
      title: "Get Aperture review",
      description:
        "Get the latest attention-compressed Markdown result.",
      inputSchema: {
        run_id: z.string().optional().describe("Optional session id")
      },
      annotations: {
        readOnlyHint: true,
        destructiveHint: false,
        openWorldHint: false
      }
    },
    async ({ run_id }) => asToolResult(await store.latestReview(run_id))
  );

  server.registerTool(
    "aperture_render_review",
    {
      title: "Show Aperture review",
      description:
        "Render the latest attention-compressed Markdown result.",
      inputSchema: {
        run_id: z.string().optional().describe("Optional session id")
      },
      _meta: {
        ui: { resourceUri: REVIEW_WIDGET_URI },
        "openai/outputTemplate": REVIEW_WIDGET_URI,
        "openai/toolInvocation/invoking": "Preparing Attention Review…",
        "openai/toolInvocation/invoked": "Attention Review ready"
      },
      annotations: {
        readOnlyHint: true,
        destructiveHint: false,
        openWorldHint: false
      }
    },
    async ({ run_id }) => asToolResult(await store.latestReview(run_id))
  );

  return server;
}

export async function handleMcpRequest(store: EventStore, req: Request, res: Response) {
  const server = createApertureMcpServer(store);
  const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined });
  try {
    await server.connect(transport);
    await transport.handleRequest(req, res, req.body);
    res.on("close", () => {
      void transport.close();
      void server.close();
    });
  } catch (error) {
    if (!res.headersSent) {
      res.status(500).json({
        jsonrpc: "2.0",
        error: {
          code: -32603,
          message: error instanceof Error ? error.message : "Internal MCP error"
        },
        id: null
      });
    }
  }
}
