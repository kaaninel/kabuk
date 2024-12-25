class Profile {
  String name;
  Email? email;
  Phone? phone;
  Address? address;
  Photo? photo;

  Profile({
    required this.name,
    this.email,
    this.phone,
    this.address,
    this.photo,
  });

  Map<String, dynamic> toJson() {
    return {
      '@type': 'Person',
      'name': name,
      'email': email?.toJson(),
      'telephone': phone?.toJson(),
      'address': address?.toJson(),
      'image': photo?.toJson(),
    };
  }
}

class Email {
  String emailAddress;
  bool isVerified;
  String domain;
  String localPart;

  Email({
    required this.emailAddress,
    this.isVerified = false,
  })  : domain = _parseDomain(emailAddress),
        localPart = _parseLocalPart(emailAddress);

  static String _parseDomain(String email) {
    final parts = email.split('@');
    if (parts.length != 2) {
      throw FormatException('Invalid email format');
    }
    return parts[1];
  }

  static String _parseLocalPart(String email) {
    final parts = email.split('@');
    if (parts.length != 2) {
      throw FormatException('Invalid email format');
    }
    return parts[0];
  }

  Map<String, dynamic> toJson() {
    return {
      '@type': 'ContactPoint',
      'email': emailAddress,
      'isVerified': isVerified,
    };
  }
}

class Phone {
  String phoneNumber;
  bool isVerified;
  String countryCode;
  String nationalNumber;

  Phone({
    required this.phoneNumber,
    this.isVerified = false,
  })  : countryCode = _parseCountryCode(phoneNumber),
        nationalNumber = _parseNationalNumber(phoneNumber);

  static String _parseCountryCode(String phone) {
    final parts = phone.split('-');
    if (parts.isEmpty) {
      throw FormatException('Invalid phone number format');
    }
    return parts[0];
  }

  static String _parseNationalNumber(String phone) {
    final parts = phone.split('-');
    if (parts.length < 2) {
      throw FormatException('Invalid phone number format');
    }
    return parts.sublist(1).join('-');
  }

  Map<String, dynamic> toJson() {
    return {
      '@type': 'ContactPoint',
      'telephone': phoneNumber,
      'isVerified': isVerified,
    };
  }
}

class Address {
  String street;
  String city;
  String state;
  String postalCode;
  String country;

  Address({
    required this.street,
    required this.city,
    required this.state,
    required this.postalCode,
    required this.country,
  });

  Map<String, dynamic> toJson() {
    return {
      '@type': 'PostalAddress',
      'streetAddress': street,
      'addressLocality': city,
      'addressRegion': state,
      'postalCode': postalCode,
      'addressCountry': country,
    };
  }
}

class Photo {
  String url;
  DateTime uploadedAt;

  Photo({
    required this.url,
    required this.uploadedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      '@type': 'ImageObject',
      'contentUrl': url,
      'uploadDate': uploadedAt.toIso8601String(),
    };
  }
}

class ChatMessage {
  final Profile sender;
  final String message;
  final DateTime timestamp;

  ChatMessage({
    required this.sender,
    required this.message,
    required this.timestamp,
  });
}

class ChatGroup {
  final String groupName;
  final List<Profile> members;
  final List<ChatMessage> messages;

  ChatGroup({
    required this.groupName,
    required this.members,
    required this.messages,
  });
}

// Example one-on-one chat data
final Profile alice = Profile(
  name: 'Alice',
  email: Email(emailAddress: 'alice@example.com'),
  phone: Phone(phoneNumber: '+1-555-1234'),
  address: Address(
    street: '123 Main St',
    city: 'Anytown',
    state: 'CA',
    postalCode: '12345',
    country: 'USA',
  ),
  photo:
      Photo(url: 'https://i.pravatar.cc/300?img=1', uploadedAt: DateTime.now()),
);

final Profile bob = Profile(
  name: 'Bob',
  email: Email(emailAddress: 'bob@example.com'),
  phone: Phone(phoneNumber: '+1-555-5678'),
  address: Address(
    street: '456 Elm St',
    city: 'Othertown',
    state: 'NY',
    postalCode: '67890',
    country: 'USA',
  ),
  photo:
      Photo(url: 'https://i.pravatar.cc/300?img=2', uploadedAt: DateTime.now()),
);

final List<ChatMessage> oneOnOneChat = [
  ChatMessage(
    sender: alice,
    message: 'Hi Bob!',
    timestamp: DateTime.now().subtract(Duration(minutes: 5)),
  ),
  ChatMessage(
    sender: bob,
    message: 'Hello Alice!',
    timestamp: DateTime.now().subtract(Duration(minutes: 4)),
  ),
  ChatMessage(
    sender: alice,
    message: 'How are you?',
    timestamp: DateTime.now().subtract(Duration(minutes: 3)),
  ),
  ChatMessage(
    sender: bob,
    message: 'I am good, thanks! How about you?',
    timestamp: DateTime.now().subtract(Duration(minutes: 2)),
  ),
];

// Example group chat data
final Profile charlie = Profile(
  name: 'Charlie',
  email: Email(emailAddress: 'charlie@example.com'),
  phone: Phone(phoneNumber: '+1-555-9012'),
  address: Address(
    street: '789 Oak St',
    city: 'Sometown',
    state: 'TX',
    postalCode: '34567',
    country: 'USA',
  ),
  photo:
      Photo(url: 'https://i.pravatar.cc/300?img=3', uploadedAt: DateTime.now()),
);

final ChatGroup groupChat = ChatGroup(
  groupName: 'Friends',
  members: [alice, bob, charlie],
  messages: [
    ChatMessage(
      sender: alice,
      message: 'Hi everyone!',
      timestamp: DateTime.now().subtract(Duration(minutes: 10)),
    ),
    ChatMessage(
      sender: bob,
      message: 'Hello Alice!',
      timestamp: DateTime.now().subtract(Duration(minutes: 9)),
    ),
    ChatMessage(
      sender: charlie,
      message: 'Hey folks!',
      timestamp: DateTime.now().subtract(Duration(minutes: 8)),
    ),
    ChatMessage(
      sender: alice,
      message: 'How are you all doing?',
      timestamp: DateTime.now().subtract(Duration(minutes: 7)),
    ),
    ChatMessage(
      sender: bob,
      message: 'I am good, thanks!',
      timestamp: DateTime.now().subtract(Duration(minutes: 6)),
    ),
    ChatMessage(
      sender: charlie,
      message: 'Doing great!',
      timestamp: DateTime.now().subtract(Duration(minutes: 5)),
    ),
  ],
);
