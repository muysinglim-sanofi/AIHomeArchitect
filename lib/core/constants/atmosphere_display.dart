/// Display-only branding for the Ayden Signature ("let AI decide" / surprise)
/// pick. The stored & routed VALUE stays the internal "AI's choice" sentinel —
/// only what the user READS is rebranded. Single source of truth shared by the
/// chat screen and the project gallery so the two displays can never desync.
///
/// Works on a bare style ("AI's choice") and on a composed title
/// ("Pool Area — AI's choice").
const String kAydenSignatureLabel = 'Ayden Signature ✦';

String brandSignature(String s) =>
    s.replaceAll("AI's choice", kAydenSignatureLabel);
