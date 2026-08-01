import {
  CheckCircle2,
  CircleDotDashed,
  Gauge,
  GitCompareArrows,
  ListTree,
  MessageSquareText,
  TriangleAlert
} from "lucide-react";
import type {
  AttentionScene,
  ComparisonVisualNode,
  FlowVisualNode,
  MetricsVisualNode,
  SceneStatus,
  StatementVisualNode,
  TextHighlight,
  VisualNode
} from "../core/types";

const statusLabels: Partial<Record<SceneStatus, string>> = {
  partial: "部分完成",
  proposed: "方案",
  unverified: "未验证"
};

function MarkedText({
  text,
  highlights
}: {
  text: string;
  highlights: TextHighlight[];
}) {
  const toneByPhrase = new Map(
    highlights
      .filter((highlight) => text.includes(highlight.phrase))
      .map((highlight) => [highlight.phrase, highlight.tone])
  );
  const phrases = [...toneByPhrase.keys()].sort(
    (left, right) => right.length - left.length
  );
  if (!phrases.length) return <>{text}</>;

  const pattern = new RegExp(
    `(${phrases.map((phrase) => phrase.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join("|")})`,
    "g"
  );
  return (
    <>
      {text.split(pattern).map((part, index) => {
        const tone = toneByPhrase.get(part);
        return tone ? (
          <mark className={`semantic-mark semantic-mark--${tone}`} key={`${index}:${part}`}>
            {part}
          </mark>
        ) : (
          part
        );
      })}
    </>
  );
}

function StatusChip({ status }: { status: SceneStatus }) {
  const label = statusLabels[status];
  if (!label) return null;
  return <span className={`scene-status scene-status--${status}`}>{label}</span>;
}

function NodeIcon({ kind, size = 15 }: { kind: VisualNode["kind"]; size?: number }) {
  if (kind === "flow") return <ListTree aria-hidden="true" size={size} />;
  if (kind === "comparison") {
    return <GitCompareArrows aria-hidden="true" size={size} />;
  }
  if (kind === "metrics") return <Gauge aria-hidden="true" size={size} />;
  return <MessageSquareText aria-hidden="true" size={size} />;
}

function SceneGateView({ scene }: { scene: AttentionScene }) {
  if (scene.gate.kind === "none") return null;
  const blocker = scene.gate.kind === "blocker";
  return (
    <aside className={`scene-gate scene-gate--${scene.gate.kind}`}>
      <header className="scene-gate-label">
        {blocker ? (
          <TriangleAlert aria-hidden="true" size={14} />
        ) : (
          <CircleDotDashed aria-hidden="true" size={14} />
        )}
        {blocker ? "阻塞" : "需要你决定"}
      </header>
      <div className="scene-gate-title">{scene.gate.title}</div>
      {scene.gate.detail && <p>{scene.gate.detail}</p>}
      {scene.gate.options.length > 0 && (
        <div className="scene-gate-options" aria-label="可选方向">
          {scene.gate.options.map((option) => (
            <span key={option}>{option}</span>
          ))}
        </div>
      )}
    </aside>
  );
}

function SceneHeader({ node }: { node: VisualNode }) {
  return (
    <header className="scene-view-header">
      <span className={`scene-kind scene-kind--${node.tone}`}>
        <NodeIcon kind={node.kind} />
      </span>
      <h2>{node.label}</h2>
      <StatusChip status={node.status} />
    </header>
  );
}

function StatementView({ node }: { node: StatementVisualNode }) {
  return (
    <section className={`scene-view scene-statement brief-view brief-view--${node.attention}`}>
      <SceneHeader node={node} />
      <p><MarkedText text={node.text} highlights={node.highlights} /></p>
    </section>
  );
}

function FlowView({ node }: { node: FlowVisualNode }) {
  return (
    <section className={`scene-view scene-flow brief-view brief-view--${node.attention}`}>
      <SceneHeader node={node} />
      <ol>
        {node.steps.map((step, index) => (
          <li className={`scene-tone--${step.tone}`} key={`${index}:${step.label}`}>
            <span className="scene-flow-index">{index + 1}</span>
            <div>
              <strong>{step.label}</strong>
              {step.detail && <p>{step.detail}</p>}
            </div>
          </li>
        ))}
      </ol>
    </section>
  );
}

function ComparisonView({ node }: { node: ComparisonVisualNode }) {
  return (
    <section className={`scene-view scene-comparison brief-view brief-view--${node.attention}`}>
      <SceneHeader node={node} />
      <div className="comparison-grid" role="table" aria-label={node.label}>
        <div className="comparison-head comparison-axis" role="columnheader">对比项</div>
        <div className="comparison-head" role="columnheader">{node.leftLabel}</div>
        <div className="comparison-head comparison-head--current" role="columnheader">{node.rightLabel}</div>
        {node.rows.map((row) => (
          <div className="comparison-row" role="row" key={row.aspect}>
            <div className="comparison-aspect" role="rowheader">{row.aspect}</div>
            <div className="comparison-cell" role="cell">{row.left}</div>
            <div className={`comparison-cell comparison-cell--${row.change}`} role="cell">
              {row.change === "better" && <CheckCircle2 aria-hidden="true" size={12} />}
              <span>{row.right}</span>
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}

function MetricsView({ node }: { node: MetricsVisualNode }) {
  return (
    <section className={`scene-view scene-metrics brief-view brief-view--${node.attention}`}>
      <SceneHeader node={node} />
      <div className="metric-grid">
        {node.items.map((item) => (
          <div className={`metric-card scene-tone--${item.tone}`} key={item.label}>
            <strong>{item.value}</strong>
            <span>{item.label}</span>
          </div>
        ))}
      </div>
    </section>
  );
}

function VisualNodeView({ node }: { node: VisualNode }) {
  if (node.kind === "flow") return <FlowView node={node} />;
  if (node.kind === "comparison") return <ComparisonView node={node} />;
  if (node.kind === "metrics") return <MetricsView node={node} />;
  return <StatementView node={node} />;
}

function SpotlightView({ scene }: { scene: AttentionScene }) {
  const statusLabel = statusLabels[scene.spotlight.status];
  return (
    <section className="brief-spotlight">
      {statusLabel && (
        <header className="brief-spotlight-meta">
          <StatusChip status={scene.spotlight.status} />
        </header>
      )}
      <h1>{scene.spotlight.label}</h1>
      <p><MarkedText text={scene.spotlight.text} highlights={scene.spotlight.highlights} /></p>
    </section>
  );
}

export function ApertureSceneView({
  scene,
  focusLevel
}: {
  scene: AttentionScene;
  focusLevel: number;
}) {
  const focusBand = focusLevel > 0.78 ? "high" : focusLevel > 0.45 ? "medium" : "balanced";
  const blocker = scene.gate.kind === "blocker";
  return (
    <div
      className={`aperture-brief aperture-brief--${focusBand}`}
      data-focus-band={focusBand}
    >
      {blocker && <SceneGateView scene={scene} />}
      <SpotlightView scene={scene} />
      {!blocker && <SceneGateView scene={scene} />}
      {scene.views.length > 0 && (
        <div className="brief-views" aria-label="完整注意力简报">
          {scene.views.map((node, index) => (
            <VisualNodeView node={node} key={`${index}:${node.kind}:${node.label}`} />
          ))}
        </div>
      )}
    </div>
  );
}
