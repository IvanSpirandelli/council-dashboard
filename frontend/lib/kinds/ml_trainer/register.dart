/// Register ML-trainer widgets in the kind registry.
///
/// MLP and GNN share `kind: ml_trainer` on the backend — the family
/// (mlps / gnns) is a panel config, not a separate kind. Both flavors
/// resolve to the same widget here. If GNN ever needs a visually
/// distinct corpus table (e.g. substrate column rendered as a column
/// instead of a chip), register a kind-specific override:
///
///   registerPanel('corpus_table', kind: 'ml_trainer',
///     (r) => MLCorpusTablePanel(response: r));
///
/// vs. a hypothetical research kind that reuses no shared panels:
///
///   registerPanel('report_view', kind: 'research',
///     (r) => MarkdownReportPanel(response: r));
///
/// Wire-up: call `registerMlTrainerKind()` once from `main.dart` at
/// app boot, alongside other kind registrations.
library;

import '../../scaffold/kind_registry.dart';
import 'corpus_table_panel.dart';

void registerMlTrainerKind() {
  registerPanel(
    'corpus_table',
    (r) => CorpusTablePanel(response: r),
  );
}
