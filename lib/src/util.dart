import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;

/// Extension with one [toShortString] method
extension RoleToShortString on types.Role {
  /// Converts enum to the string equal to enum's name
  String toShortString() {
    return toString().split('.').last;
  }
}

/// Extension with one [toShortString] method
extension RoomTypeToShortString on types.RoomType {
  /// Converts enum to the string equal to enum's name
  String toShortString() {
    return toString().split('.').last;
  }
}

/// Fetches user from Firebase and returns a promise
Future<Map<String, dynamic>> fetchUser(
  FirebaseFirestore instance,
  String userId,
  String usersCollectionName, {
  String? role,
}) async {
  final doc = await instance.collection(usersCollectionName).doc(userId).get();

  final data = doc.data()!;

  data['createdAt'] = data['createdAt']?.millisecondsSinceEpoch;
  data['id'] = doc.id;
  data['lastSeen'] = data['lastSeen']?.millisecondsSinceEpoch;
  data['role'] = role;
  data['updatedAt'] = data['updatedAt']?.millisecondsSinceEpoch;

  return data;
}

/// Returns a list of [types.Room] created from Firebase query.
/// If room has 2 participants, sets correct room name and image.
Future<List<types.Room>> processRoomsQuery(
  User firebaseUser,
  FirebaseFirestore instance,
  QuerySnapshot<Map<String, dynamic>> query,
  String usersCollectionName,
) async {
  final futures = query.docs.map(
    (doc) => processRoomDocument(
      doc,
      firebaseUser,
      instance,
      usersCollectionName,
    ),
  );

  return await Future.wait(futures);
}

Future<types.Room> preProcessRoomDocument(
  List<DocumentSnapshot<Map<String, dynamic>>> doc,
  User firebaseUser,
  FirebaseFirestore instance,
  String usersCollectionName,
  String otherUserID,
) {
  if (doc.isNotEmpty) {
    print('user has chats');
    DocumentSnapshot<Map<String, dynamic>> docNew = doc.first;

    for (int i = 0; i < doc.length; i++) {
      final data = doc[i].data()!;
      final userIds = data['userIds'] as List<dynamic>;

      if (userIds.contains(firebaseUser.uid)) {
        docNew = doc[i];
        print('user found chats');

        break;
      }
    }

    return processRoomDocument(
      docNew,
      firebaseUser,
      instance,
      usersCollectionName,
    );
  } else {
    return createRoom(instance, firebaseUser, otherUserID);
  }
}

Future<types.Room> createRoom(
  FirebaseFirestore instance,
  User cUser,
  String otherUserID, {
  Map<String, dynamic>? metadata,
}) async {
  print('createRoom calls');

  final currentUser = await fetchUser(
    instance,
    cUser.uid,
    'users',
  );

  final otherUser = await fetchUser(
    instance,
    otherUserID,
    'users',
  );

  final users = [
    types.User.fromJson(currentUser),
    types.User.fromJson(otherUser)
  ];
  print('users created');

  final room = await instance.collection('rooms').add({
    'createdAt': FieldValue.serverTimestamp(),
    'imageUrl': null,
    'metadata': metadata,
    'name': null,
    'type': types.RoomType.direct.toShortString(),
    'updatedAt': FieldValue.serverTimestamp(),
    'userIds': users.map((u) => u.id).toList(),
    'userRoles': null,
  });

  print('room created');

  return types.Room(
    id: room.id,
    metadata: metadata,
    type: types.RoomType.direct,
    users: users,
  );
}

/// Returns a [types.Room] created from Firebase document
Future<types.Room> processRoomDocument(
  DocumentSnapshot<Map<String, dynamic>> doc,
  User firebaseUser,
  FirebaseFirestore instance,
  String usersCollectionName,
) async {
  final data = doc.data()!;

  data['createdAt'] = data['createdAt']?.millisecondsSinceEpoch;
  data['id'] = doc.id;
  data['updatedAt'] = data['updatedAt']?.millisecondsSinceEpoch;

  var imageUrl = data['imageUrl'] as String?;
  var name = data['name'] as String?;
  final type = data['type'] as String;
  final userIds = data['userIds'] as List<dynamic>;
  final userRoles = data['userRoles'] as Map<String, dynamic>?;

  final users = await Future.wait(
    userIds.map(
      (userId) => fetchUser(
        instance,
        userId as String,
        usersCollectionName,
        role: userRoles?[userId] as String?,
      ),
    ),
  );

  if (type == types.RoomType.direct.toShortString()) {
    try {
      final otherUser = users.firstWhere(
        (u) => u['id'] != firebaseUser.uid,
      );

      imageUrl = otherUser['imageUrl'] as String?;
      name = '${otherUser['firstName'] ?? ''} ${otherUser['lastName'] ?? ''}'
          .trim();
    } catch (e) {
      // Do nothing if other user is not found, because he should be found.
      // Consider falling back to some default values.
    }
  }

  data['imageUrl'] = imageUrl;
  data['name'] = name;
  data['users'] = users;

  if (data['lastMessages'] != null) {
    final lastMessages = data['lastMessages'].map((lm) {
      final author = users.firstWhere(
        (u) => u['id'] == lm['authorId'],
        orElse: () => {'id': lm['authorId'] as String},
      );

      lm['author'] = author;
      lm['createdAt'] = lm['createdAt']?.millisecondsSinceEpoch;
      lm['id'] = lm['id'] ?? '';
      lm['updatedAt'] = lm['updatedAt']?.millisecondsSinceEpoch;

      return lm;
    }).toList();

    data['lastMessages'] = lastMessages;
  }

  return types.Room.fromJson(data);
}