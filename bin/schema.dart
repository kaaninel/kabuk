import 'dart:convert';
import 'dart:io' as io;

void main() async {
  final url = "asset/schema/schemaorg-current-https.jsonld";
  final root =
      await io.File(url).readAsString().then((jsonStr) => jsonDecode(jsonStr));

  final graph = root['@graph'] as List;
  final classes = _extractEntities(graph, 'rdfs:Class');
  final properties = _extractEntities(graph, 'rdf:Property');
  final dataTypes = _extractEntities(graph, 'schema:DataType');

  final propMap = _buildPropertyMap(properties);

  io.Directory("lib/schema").createSync(recursive: false);

  for (final cls in classes.entries) {
    final props = propMap[cls.value["@id"]] ?? [];

    final classText = _buildClass(cls, properties, props);
    final fileUrl = "lib/schema/${_toSnakeCase(cls.key.split(":").last)}.dart";
    await io.File(fileUrl).writeAsString(classText);
  }
}

Map<String, Map<String, dynamic>> _extractEntities(List graph, String type) {
  return Map<String, Map<String, dynamic>>.fromEntries(
      graph.where((e) => e['@type'] == type).map((e) => MapEntry(e["@id"], e)));
}

Map<String, List<String>> _buildPropertyMap(
    Map<String, Map<String, dynamic>> properties) {
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
  return propMap;
}

String _buildClass(MapEntry<String, Map<String, dynamic>> cls,
    Map<String, dynamic> properties, List<String> props) {
  final inheritance = _extractInheritance(cls);
  final ranges = _extractRanges(props, properties);
  final inheritanceImport = inheritance.map(_toSnakeCase).toSet();

  final sb = StringBuffer();
  _writeImports(sb, inheritanceImport, ranges);
  _writeProperties(sb, cls, properties, props);
  _writeClassDefinition(sb, cls, inheritance, props, properties);

  return sb.toString();
}

List<String> _extractInheritance(MapEntry<String, Map<String, dynamic>> cls) {
  return <String>[
    if (cls.value["rdfs:subClassOf"] is List)
      for (final parent in cls.value["rdfs:subClassOf"])
        parent["@id"].split(":").last
    else if (cls.value["rdfs:subClassOf"] is Map)
      cls.value["rdfs:subClassOf"]["@id"].split(":").last
  ];
}

Set<String> _extractRanges(
    List<String> props, Map<String, dynamic> properties) {
  return props
      .map((prop) => properties[prop]?["schema:rangeIncludes"])
      .expand((e) => e is List ? e : [e])
      .map<String>((e) => e["@id"].split(":").last)
      .map<String>(_toSnakeCase)
      .toSet();
}

void _writeImports(
    StringBuffer sb, Set<String> inheritanceImport, Set<String> ranges) {
  for (final range in inheritanceImport) {
    sb.writeln('import "package:kabuk/schema/$range.dart";');
  }
  for (final range in ranges) {
    sb.writeln('import "package:kabuk/schema/$range.dart";');
  }
}

void _writeProperties(
    StringBuffer sb,
    MapEntry<String, Map<String, dynamic>> cls,
    Map<String, dynamic> properties,
    List<String> props) {
  for (final prop in props) {
    final propDef = properties[prop];
    final range = propDef?["schema:rangeIncludes"];
    if (range is List) {
      final baseClass =
          [cls.key.split(":").last, propDef["@id"].split(":").last].join("");
      sb.writeln();
      sb.writeln("sealed class $baseClass {}");
      for (final r in range) {
        final rangeType = r["@id"].split(":").last;
        sb.writeln();
        sb.writeln('class $baseClass$rangeType extends $baseClass {');
        sb.writeln("  $rangeType value;");
        sb.writeln("}");
      }
      sb.writeln();
    }
  }
}

void _writeClassDefinition(
    StringBuffer sb,
    MapEntry<String, Map<String, dynamic>> cls,
    List<String> inheritance,
    List<String> props,
    Map<String, dynamic> properties) {
  sb.writeln();
  _extractComment(cls.value).split("\n").forEach((line) {
    sb.writeln("  /// $line");
  });
  final inheritenceText =
      inheritance.isNotEmpty ? "implements ${inheritance.join(", ")}" : "";

  sb.writeln("class ${cls.key.split(":").last} $inheritenceText {");
  for (final prop in props) {
    final propDef = properties[prop];
    final range = propDef?["schema:rangeIncludes"];
    final rangeType = range is Map
        ? range["@id"].split(":").last
        : [cls.key.split(":").last, propDef["@id"].split(":").last].join("");

    _extractComment(propDef).split("\n").forEach((line) {
      sb.writeln("  /// $line");
    });
    sb.writeln("  $rangeType ${propDef?["@id"].split(":").last};");
  }
  sb.writeln("}");
}

String _toSnakeCase(String input) {
  final result = StringBuffer();

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

  return result
      .toString()
      .replaceAllMapped(
          RegExp(r'([A-Z]+)([A-Z][a-z])'), (Match m) => '${m[1]}_${m[2]}')
      .toLowerCase();
}

String _extractComment(Map<String, dynamic> propDef) {
  final comment = propDef["rdfs:comment"];
  return comment is String
      ? comment
      : comment is Map
          ? comment.entries
              .where((e) => e.key.startsWith("@en"))
              .map((e) => e.value)
              .join("\n")
          : "No comment found";
}
