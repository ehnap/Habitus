final _secretQuery = RegExp(
  r'([?&](?:t|s|p|apiKey|password|token)=)[^&\s#]+',
  caseSensitive: false,
);

String redactSecrets(String input) {
  return input.replaceAllMapped(_secretQuery, (match) => '${match.group(1)}***');
}
