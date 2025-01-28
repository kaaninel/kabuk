import "package:test/test.dart";
import "package:schema/src/memory.dart";
import "package:schema/schema.dart";

void main() {
  group("Memory class", () {
    late Memory memory;
    final kaan = Subject.ref("me:Kaan Inel");
    final huseyin = Subject.ref("me:Huseyin Akbas");
    final follows = Predicate.schema("Follows");

    setUp(() {
      memory = Memory("test_agent");
    });

    test("creates a new Memory instance", () {
      expect(memory.id, equals("test_agent"));
      memory.close();
    });

    test("adds and retrieves data", () {
      final data = Data(
          null,
          kaan, huseyin.toRefObject(), follows, null);
      memory.add(data);
      final results = memory.find(subject: kaan).toList();
      expect(results.length, equals(1));
      expect(results.first.subject?.value, equals(kaan.value));
      memory.close();
    });
  });
}
