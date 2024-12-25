import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  final url =
      'https://schema.org/version/latest/schemaorg-current-https.jsonld';
  final response = await http.get(Uri.parse(url));

  if (response.statusCode == 200) {
    final jsonData = jsonDecode(response.body);
    await generateDartClasses(jsonData);
  } else {
    print('Failed to load schema.org JSON-LD file');
  }
}

Future<void> generateDartClasses(Map<String, dynamic> jsonData) async {
  final graph = jsonData['@graph'];

  for (var item in graph) {
    if (item['@type'] == 'rdfs:Class') {
      final className = item['rdfs:label'];
      final properties = item['http://schema.org/domainIncludes'] ?? [];

      final buffer = StringBuffer();
      buffer.writeln('class $className {');
      for (var property in properties) {
        final propertyName = property['rdfs:label'][0]['@value'];
        final propertyType = property['@type'];
        buffer.writeln('  $propertyType $propertyName;');
      }
      buffer.writeln();
      buffer.writeln('  $className({');
      for (var property in properties) {
        final propertyName = property['rdfs:label'][0]['@value'];
        buffer.writeln('    required this.$propertyName,');
      }
      buffer.writeln('  });');
      buffer.writeln('}');
      buffer.writeln();

      final outputFileName = toSnakeCase(className);
      final outputFile = File('lib/schema/$outputFileName.dart');
      await outputFile.writeAsString(buffer.toString());
    }
  }
}

String toSnakeCase(String input) {
  final RegExp upperAlphaRegex = RegExp(r'[A-Z]');
  final RegExp lowerAlphaRegex = RegExp(r'[a-z]');
  final RegExp numericRegex = RegExp(r'[0-9]');

  StringBuffer buffer = StringBuffer();
  for (int i = 0; i < input.length; i++) {
    String char = input[i];
    if (upperAlphaRegex.hasMatch(char)) {
      if (i > 0 &&
          (lowerAlphaRegex.hasMatch(input[i - 1]) ||
              numericRegex.hasMatch(input[i - 1]))) {
        buffer.write('_');
      }
      buffer.write(char.toLowerCase());
    } else {
      buffer.write(char);
    }
  }
  return buffer.toString();
}
