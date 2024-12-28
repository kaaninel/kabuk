import 'dart:convert';
import 'dart:io' as io;

void main() async {
  final url = "asset/schema/schemaorg-current-https.jsonld";
  final root =
      await io.File(url).readAsString().then((jsonStr) => jsonDecode(jsonStr));

  final graph = root['@graph'] as List;
  final classes = Map<String, Map<String, dynamic>>.fromEntries(graph
      .where((e) => e['@type'] == 'rdfs:Class')
      .map((e) => MapEntry(e["@id"], e)));
  final properties = Map<String, Map<String, dynamic>>.fromEntries(graph
      .where((e) => e['@type'] == 'rdf:Property')
      .map((e) => MapEntry(e["@id"], e)));
  final Map<String, List<String>> propMap = {};
  for (final prop in properties.values) {
    final includes = prop["schema:domainIncludes"];
    if (includes is List) {
      for (final cls in includes) {
        propMap.putIfAbsent(cls["@id"], () => []).add(prop["@id"]);
      }
    } else if (includes is Map) {
      propMap.putIfAbsent(includes["@id"], () => []).add(prop["@id"]);
    }
  }

  io.Directory("lib/schema").createSync(recursive: false);

  for (final cls in classes.entries) {
    final props = propMap[cls.value["@id"]];
    if (props == null) {
      continue;
    }
    final classText = classBuild(cls, properties, props);
    final fileUrl =
        "lib/schema/${classToFileName(cls.key.split(":").last)}.dart";
    await io.File(fileUrl).writeAsString(classText);
  }
}

String classBuild(MapEntry<String, Map<String, dynamic>> cls,
    Map<String, dynamic> properties, List<String> props) {
  final inheritence = <String>[
    if (cls.value["rdfs:subClassOf"] is List)
      for (final parent in cls.value["rdfs:subClassOf"])
        parent["@id"].split(":").last
    else if (cls.value["rdfs:subClassOf"] is Map)
      cls.value["rdfs:subClassOf"]["@id"].split(":").last
  ];

  final ranges = props
      .map((prop) => properties[prop]?["schema:rangeIncludes"])
      .expand((e) => e is List ? e : [e])
      .map<String>((e) => e["@id"].split(":").last)
      .map<String>(classToFileName)
      .toSet();
  final inheritenceImport = inheritence.map(classToFileName).toSet();

  StringBuffer sb = StringBuffer();
  for (final range in inheritenceImport) {
    sb.writeln('import "package:kabuk/schema/$range.dart";');
  }
  for (final range in ranges) {
    sb.writeln('import "package:kabuk/schema/$range.dart";');
  }
  sb.writeln();
  extractComment(cls.value).split("\n").forEach((line) {
    sb.writeln("  /// $line");
  });
  sb.writeln("class ${cls.key.split(":").last} implements ${[
    "Object",
    ...inheritence
  ].join(", ")} {");
  for (final prop in props) {
    final propDef = properties[prop];
    final range = propDef?["schema:rangeIncludes"];
    final rangeType = range is Map
        ? range["@id"].split(":").last
        : "OneOf<${range.map((e) => e["@id"].split(":").last).join(",")}>";

    extractComment(propDef).split("\n").forEach((line) {
      sb.writeln("  /// $line");
    });
    sb.writeln("  $rangeType ${propDef?["@id"].split(":").last};");
  }
  sb.writeln("}");
  return sb.toString();
}

String classToFileName(String input) {
  final result = StringBuffer();

  // If the first character is a number, prepend 'schema_'
  if (input.isNotEmpty && RegExp(r'^[0-9]').hasMatch(input)) {
    result.write('schema_');
  }

  for (int i = 0; i < input.length; i++) {
    if (i > 0 &&
        input[i].toUpperCase() == input[i] &&
        input[i - 1].toUpperCase() != input[i - 1]) {
      result.write('_');
    }
    result.write(input[i]);
  }

  final snakeCase = result
      .toString()
      .replaceAllMapped(
          RegExp(r'([A-Z]+)([A-Z][a-z])'), (Match m) => '${m[1]}_${m[2]}')
      .toLowerCase();

  return snakeCase;
}

String extractComment(Map<String, dynamic> propDef) {
  final comment = propDef["rdfs:comment"];
  final enComment = comment is String
      ? comment
      : comment is Map
          ? comment.entries
              .where((e) => e.key.startsWith("@en"))
              .map((e) => e.value)
              .join("\n")
          : "No comment found";
  return enComment;
}
