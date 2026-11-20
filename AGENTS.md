<!-- agents-local:begin -->
Codex only: if `AGENTS.local.md` exists next to this file, read it before starting. Claude Code already loads it through `CLAUDE.local.md`; do not read it again.
<!-- agents-local:end -->
This file is published with the source. Never write paths, personal data, or names of the local environment into it.

# ArchiveLeaf Agent Instructions

説明（日本語）: このファイルでは、英語の箇条書きと番号付き項目が実行指示です。日本語文は、指示の意図と運用上の背景を説明する補助文です。

## Instruction layout

説明（日本語）: CodexとClaude Codeが同じプロジェクトを共有するための取り決めです。片方の都合で共有部分を削ると、もう片方が規約を失います。所有者の書かれていない節は共有です。

- Read `AGENTS.md` as the shared substrate. Codex loads it natively; Claude Code loads it by importing it from `CLAUDE.md`.
- Keep `AGENTS.md` self-sufficient for Codex. Do not move a shared rule into a file that only one tool can read.
- Mark a section `Codex-only` or `Claude-only` when it does not apply to both. Leave shared sections unmarked.
- Do not delete or narrow a shared section to suit one tool. Add a tool-specific section instead.
- Keep tool-specific mechanisms in that tool's own area: Claude Code skills, hooks, and subagents under `.claude/`; Codex settings under `.codex/`.
- Put only procedure into a tool-specific mechanism. A rule the other tool must also obey belongs in a shared section, even when one tool can enforce it mechanically.

## Source of truth

説明（日本語）: 現在の依頼、Gitで追跡されている実装とテスト、設計文書の方針を主な判断材料にします。

- Follow the current user request first.
- Use the tracked source and tests at the current Git revision as the implementation state.
- Use `docs/DESIGN.md` for product direction and durable design principles, and `README.md` for building and running.
- When sources conflict, report the conflict instead of silently choosing or rewriting project intent.

## Project invariants

説明（日本語）: ArchiveLeafの中心的な製品境界と、既存実装で守るべき長期原則だけをここに置きます。詳細仕様は設計文書とコード側を正とし、このファイルへ重複して増やしません。

- Treat ArchiveLeaf as a read-only personal shelf for macOS, iOS, and iPadOS.
- Keep CloudKit Private Database as the data source of truth and imported content immutable.
- Prefer Apple-standard controls and platform-adaptive behavior.
- Keep platform-specific code isolated and preserve existing service boundaries.
- Do not add dependencies or broaden the product scope without explicit approval.

## Privacy by design

説明（日本語）: ログへ書いた情報は後から完全・選択的に消せるとは限りません。診断の都合より先に、収集しない境界を設計します。

- Treat data minimization as a design input from the first implementation, not as cleanup after logging exists.
- Do not log user content or identifiers derived from it: filenames, URLs, paths, folder or tag names, document text, page numbers, browsing history, selections, CloudKit record identifiers, or local asset identifiers.
- When diagnostics are necessary, prefer fixed event names, coarse error categories, counts, durations, and boolean outcomes that cannot reconstruct what the user viewed or stored.
- Do not interpolate raw system or framework error descriptions into persistent logs when they may contain user data. Map them to reviewed categories first.
- Keep diagnostic logging off unless it has a concrete troubleshooting purpose, and review every new log statement for privacy before accepting it.
- Apply these defaults to new projects and features unless the user explicitly approves a narrower, documented exception.

## Before editing

説明（日本語）: 既存変更と現在の設計を確認してから、変更範囲と検証方法を決めます。ユーザーの作業を上書きせず、既存パターンを優先します。

1. Check Git status and preserve existing user changes.
2. Read the relevant parts of `docs/DESIGN.md`, the current implementation, and related tests. Choose those parts from the `Index` section at the top of `docs/DESIGN.md` and read only the sections it names; do not read the whole file.
3. State the goal, assumptions, affected files, risks, reusable material, and verification plan before editing.
4. Reuse existing patterns and tests before introducing new abstractions.
5. Keep the change focused and report unrelated problems separately.

## Verification

説明（日本語）: 通常テストはCloudKit実データへ触れない経路を使います。

- Use `scripts/test-macos-memory.sh` for routine macOS tests.
- Keep CloudKit integration tests opt-in and run them only when their data effects and environment are explicitly understood and approved.
- Keep the development team ID in `Config/Developer.xcconfig`. Do not let it be written into `project.pbxproj`.
- Verify behavior, appearance, and operability at the relevant platform sizes and states.
- Review the final diff for architecture consistency, regressions, unnecessary changes, and missing tests before declaring completion.
