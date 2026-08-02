import type { AppLanguage } from "../core/types";

const messages = {
  cn: {
    unknownProject: "未知工程",
    paused: "已暂停",
    waiting: "等待中",
    reviewLabel: "Aperture 处理结果",
    copied: "已复制",
    copyReview: "复制选中内容或全部内容",
    partial: "部分完成",
    proposed: "方案",
    unverified: "未验证",
    done: "已完成",
    decision: "需要你决定",
    blocker: "阻塞",
    options: "可选方向",
    comparison: "对比项",
    completeBrief: "完整注意力简报",
    action: "下一步",
    risk: "风险",
    reference: "参考",
    showMore: (count: number) => `展开其余 ${count} 条信息`
  },
  en: {
    unknownProject: "Unknown project",
    paused: "Paused",
    waiting: "Waiting",
    reviewLabel: "Aperture result",
    copied: "Copied",
    copyReview: "Copy selection or all content",
    partial: "Partially complete",
    proposed: "Proposed",
    unverified: "Unverified",
    done: "Done",
    decision: "Decision needed",
    blocker: "Blocked",
    options: "Options",
    comparison: "Comparison",
    completeBrief: "Complete attention brief",
    action: "Next step",
    risk: "Risk",
    reference: "Reference",
    showMore: (count: number) => `Show ${count} more ${count === 1 ? "item" : "items"}`
  }
} as const;

export function ui(language: AppLanguage) {
  return messages[language];
}
