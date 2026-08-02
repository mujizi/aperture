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
  AppLanguage,
  AttentionScene,
  ComparisonVisualNode,
  FlowVisualNode,
  MetricsVisualNode,
  SceneStatus,
  StatementVisualNode,
  TextHighlight,
  VisualNode
} from "../core/types";
import { ui } from "./i18n";

function statusLabel(status: SceneStatus, language: AppLanguage) {
  const labels = ui(language);
  return status === "partial" ? labels.partial
    : status === "proposed" ? labels.proposed
    : status === "unverified" ? labels.unverified
    : undefined;
}

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

function StatusChip({ status, language }: { status: SceneStatus; language: AppLanguage }) {
  const label = statusLabel(status, language);
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

function SceneGateView({ scene, language }: { scene: AttentionScene; language: AppLanguage }) {
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
        {blocker ? ui(language).blocker : ui(language).decision}
      </header>
      <div className="scene-gate-title">{scene.gate.title}</div>
      {scene.gate.detail && <p>{scene.gate.detail}</p>}
      {scene.gate.options.length > 0 && (
        <div className="scene-gate-options" aria-label={ui(language).options}>
          {scene.gate.options.map((option) => (
            <span key={option}>{option}</span>
          ))}
        </div>
      )}
    </aside>
  );
}

function SceneHeader({ node, language }: { node: VisualNode; language: AppLanguage }) {
  return (
    <header className="scene-view-header">
      <span className={`scene-kind scene-kind--${node.tone}`}>
        <NodeIcon kind={node.kind} />
      </span>
      <h2>{node.label}</h2>
      <StatusChip status={node.status} language={language} />
    </header>
  );
}

function StatementView({ node, language }: { node: StatementVisualNode; language: AppLanguage }) {
  return (
    <section className={`scene-view scene-statement brief-view brief-view--${node.attention}`}>
      <SceneHeader node={node} language={language} />
      <p><MarkedText text={node.text} highlights={node.highlights} /></p>
    </section>
  );
}

function FlowView({ node, language }: { node: FlowVisualNode; language: AppLanguage }) {
  return (
    <section className={`scene-view scene-flow brief-view brief-view--${node.attention}`}>
      <SceneHeader node={node} language={language} />
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

function ComparisonView({ node, language }: { node: ComparisonVisualNode; language: AppLanguage }) {
  return (
    <section className={`scene-view scene-comparison brief-view brief-view--${node.attention}`}>
      <SceneHeader node={node} language={language} />
      <div className="comparison-grid" role="table" aria-label={node.label}>
        <div className="comparison-head comparison-axis" role="columnheader">{ui(language).comparison}</div>
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

function MetricsView({ node, language }: { node: MetricsVisualNode; language: AppLanguage }) {
  return (
    <section className={`scene-view scene-metrics brief-view brief-view--${node.attention}`}>
      <SceneHeader node={node} language={language} />
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

function VisualNodeView({ node, language }: { node: VisualNode; language: AppLanguage }) {
  if (node.kind === "flow") return <FlowView node={node} language={language} />;
  if (node.kind === "comparison") return <ComparisonView node={node} language={language} />;
  if (node.kind === "metrics") return <MetricsView node={node} language={language} />;
  return <StatementView node={node} language={language} />;
}

function SpotlightView({ scene, language }: { scene: AttentionScene; language: AppLanguage }) {
  const label = statusLabel(scene.spotlight.status, language);
  return (
    <section className="brief-spotlight">
      {label && (
        <header className="brief-spotlight-meta">
          <StatusChip status={scene.spotlight.status} language={language} />
        </header>
      )}
      <h1>{scene.spotlight.label}</h1>
      <p><MarkedText text={scene.spotlight.text} highlights={scene.spotlight.highlights} /></p>
    </section>
  );
}

export function ApertureSceneView({
  scene,
  focusLevel,
  language = "cn"
}: {
  scene: AttentionScene;
  focusLevel: number;
  language?: AppLanguage;
}) {
  const focusBand = focusLevel > 0.78 ? "high" : focusLevel > 0.45 ? "medium" : "balanced";
  const blocker = scene.gate.kind === "blocker";
  return (
    <div
      className={`aperture-brief aperture-brief--${focusBand}`}
      data-focus-band={focusBand}
    >
      {blocker && <SceneGateView scene={scene} language={language} />}
      <SpotlightView scene={scene} language={language} />
      {!blocker && <SceneGateView scene={scene} language={language} />}
      {scene.views.length > 0 && (
        <div className="brief-views" aria-label={ui(language).completeBrief}>
          {scene.views.map((node, index) => (
            <VisualNodeView node={node} language={language} key={`${index}:${node.kind}:${node.label}`} />
          ))}
        </div>
      )}
    </div>
  );
}
