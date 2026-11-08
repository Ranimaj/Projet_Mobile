/// Clé de l'API Gemini enregistrée dans l'app (Google AI Studio).
///
/// Dans Git, elle reste VIDE : une clé publiée sur GitHub est désactivée par
/// Google. Sur ton PC, mets ta clé entre les guillemets ; le script
/// `proteger_cle_gemini.bat` dit à Git d'ignorer ce changement
/// (`git update-index --skip-worktree`), il ne partira donc jamais sur GitHub.
const String kGeminiApiKeyLocal = '';
