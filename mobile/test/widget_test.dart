// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';

import 'package:community_chat/core/theme.dart';
import 'package:community_chat/models/chat_item.dart';
import 'package:community_chat/providers/auth_provider.dart';
import 'package:community_chat/providers/community_provider.dart';
import 'package:community_chat/screens/chats/message_bubble.dart';
import 'package:community_chat/screens/chats/image_message_bubble.dart';
import 'package:community_chat/screens/auth/auth_screen.dart';
import 'package:community_chat/screens/welcome_screen.dart';
import 'package:community_chat/services/crypto_service.dart';
import 'package:community_chat/services/image_processing_service.dart';
import 'package:community_chat/screens/home_screen.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('welcome screen offers account creation', (tester) async {
    final provider = AuthProvider()..isInitialized = true;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: WelcomeScreen()),
      ),
    );

    expect(find.text('Community Chat'), findsOneWidget);
    expect(find.text('I\'m new — Create account'), findsOneWidget);
  });

  testWidgets('registration asks only for a user name and four-digit PIN', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthProvider(),
        child: const MaterialApp(home: AuthScreen(mode: AuthMode.register)),
      ),
    );

    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('User name'), findsOneWidget);
    expect(find.text('4-digit PIN'), findsOneWidget);
    expect(find.text('Display name'), findsNothing);
    expect(find.text('Community invite code'), findsNothing);

    await tester.enterText(find.byType(TextFormField).last, '12345');
    await tester.pump();
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).last)
          .controller!
          .text,
      '1234',
    );
  });

  testWidgets('remembered account unlock asks for PIN only', (tester) async {
    final provider = AuthProvider()
      ..isInitialized = true
      ..rememberedUserId = 'moin';
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: AuthScreen(mode: AuthMode.pinUnlock)),
      ),
    );

    expect(find.text('Welcome back, @moin'), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);
    expect(find.text('User name'), findsNothing);
    expect(find.text('4-digit PIN'), findsOneWidget);
    expect(find.text('Use another account'), findsOneWidget);
  });

  testWidgets('chat button opens neighbour search', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => CommunityProvider()),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Find a neighbour').first);
    await tester.pumpAndSettle();

    expect(find.text('Search by exact user ID'), findsOneWidget);
    expect(find.text('Send connection request'), findsNothing);
  });

  testWidgets('home navigation stays in sync at narrow width and larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final communityProvider = CommunityProvider();
    addTearDown(communityProvider.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider<CommunityProvider>.value(
            value: communityProvider,
          ),
        ],
        child: MaterialApp(
          theme: CommunityTheme.light(),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.3)),
              child: const HomeScreen(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    communityProvider.chats = [
      ChatItem(
        id: 'chat-1',
        name: 'A very long community member name',
        lastMessage: 'Encrypted message',
        timestamp: DateTime.now(),
        unreadCount: 12,
        online: true,
        avatarColor: AppColors.avatarFallbackBg,
      ),
    ];
    communityProvider.notifyListeners();
    await tester.pump();
    expect(find.text('Encrypted message'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final navigationBar = find.byType(NavigationBar);
    expect(tester.widget<NavigationBar>(navigationBar).selectedIndex, 0);

    await tester.tap(
      find.descendant(of: navigationBar, matching: find.text('Requests')),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(navigationBar).selectedIndex, 1);

    await tester.drag(find.byType(TabBarView), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(navigationBar).selectedIndex, 2);
    expect(tester.takeException(), isNull);
  });

  test('chat history sender field maps to a normalized sender ID', () {
    final message = ChatMessage.fromJson({
      'id': 'message-1',
      'sender': {'_id': ' User-A '},
      'payload': 'hello',
    });

    expect(message.senderId, 'User-A');
    expect(message.text, 'hello');
  });

  test('chat history retains read receipt timestamp', () {
    final message = ChatMessage.fromJson({
      'id': 'message-read',
      'senderId': 'user-a',
      'payload': 'enc1:ZW5jcnlwdGVk',
      'createdAt': '2026-01-02T13:05:00.000Z',
      'readAt': '2026-01-02T13:06:00.000Z',
    });

    expect(message.readAt, DateTime.parse('2026-01-02T13:06:00.000Z'));
  });

  test(
    'image messages retain image data and optional captions from history',
    () {
      final message = ChatMessage.fromJson({
        'id': 'image-1',
        'senderId': 'user-a',
        'type': 'image',
        'imageUrl': '/api/media/media-1',
        'caption': 'A photo',
      });

      expect(message.type, 'image');
      expect(message.imageUrl, '/api/media/media-1');
      expect(message.caption, 'A photo');
    },
  );

  test('image processor accepts PNG and outputs a compressed JPEG', () {
    final png = Uint8List.fromList(
      img.encodePng(img.Image(width: 2, height: 2)),
    );
    final processed = ImageProcessingService().process(png);

    expect(processed.contentType, 'image/jpeg');
    expect(processed.bytes.take(3), [0xff, 0xd8, 0xff]);
    expect(processed.bytes.lengthInBytes, lessThan(5 * 1024 * 1024));
  });

  test('image processor rejects unsupported file signatures', () {
    expect(
      () => ImageProcessingService().process(Uint8List.fromList([1, 2, 3])),
      throwsA(isA<ImagePreparationException>()),
    );
  });

  test(
    'two chat identities derive the same key and encrypt text and images',
    () async {
      final crypto = CryptoService();
      final senderPair = await crypto.generateKeyPair();
      final receiverPair = await crypto.generateKeyPair();
      final senderPublicKey = await crypto.publicKeyToBase64(senderPair);
      final receiverPublicKey = await crypto.publicKeyToBase64(receiverPair);
      final senderKey = await crypto.deriveChatKey(
        'chat-1',
        receiverPublicKey,
        senderPair,
      );
      final receiverKey = await crypto.deriveChatKey(
        'chat-1',
        senderPublicKey,
        receiverPair,
      );
      expect(senderKey, receiverKey);

      final encryptedText = await crypto.encryptText(
        'hello',
        'chat-1',
        'sender-id',
        senderKey,
      );
      expect(encryptedText, startsWith('enc1:'));
      final decryptedText = await crypto.decryptText(
        encryptedText,
        'chat-1',
        'sender-id',
        receiverKey,
      );
      expect(decryptedText, {'ok': true, 'text': 'hello'});

      final image = Uint8List.fromList([0xff, 0xd8, 0xff, 1, 2, 3]);
      final encryptedImage = await crypto.encryptBytes(
        image,
        'chat-1',
        'sender-id',
        senderKey,
        type: 'image',
      );
      final decryptedImage = await crypto.decryptBytes(
        encryptedImage,
        'chat-1',
        'sender-id',
        receiverKey,
        type: 'image',
      );
      expect(decryptedImage, image);
      await expectLater(
        crypto.decryptBytes(
          encryptedImage,
          'different-chat',
          'sender-id',
          receiverKey,
          type: 'image',
        ),
        throwsA(isA<Exception>()),
      );
    },
  );

  testWidgets('sender image is right-aligned in the outgoing bubble', (
    tester,
  ) async {
    final bytes = Uint8List.fromList(
      img.encodePng(img.Image(width: 2, height: 2)),
    );
    const message = ChatMessage(
      id: 'image-1',
      senderId: 'user-a',
      text: '',
      type: 'image',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImageMessageBubble(
            message: message.copyWith(localImageBytes: bytes),
            currentUserId: 'user-a',
            maxWidth: 240,
          ),
        ),
      ),
    );

    final bubbleFinder = find.descendant(
      of: find.byType(ImageMessageBubble),
      matching: find.byType(Align),
    );
    final bubble = tester.widget<Align>(bubbleFinder.first);
    expect(bubble.alignment, Alignment.centerRight);
    final bubbleContainer = tester.widget<Container>(
      find.descendant(
        of: find.byType(ImageMessageBubble),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).color ==
                  CommunityTheme.bubbleOut,
        ),
      ),
    );
    expect(
      (bubbleContainer.decoration! as BoxDecoration).color,
      CommunityTheme.bubbleOut,
    );
  });

  testWidgets('received image is left-aligned in the incoming bubble', (
    tester,
  ) async {
    final bytes = Uint8List.fromList(
      img.encodePng(img.Image(width: 2, height: 2)),
    );
    const message = ChatMessage(
      id: 'image-2',
      senderId: 'user-a',
      text: '',
      type: 'image',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImageMessageBubble(
            message: message.copyWith(localImageBytes: bytes),
            currentUserId: 'user-b',
            maxWidth: 240,
          ),
        ),
      ),
    );

    final bubble = tester.widget<Align>(
      find
          .descendant(
            of: find.byType(ImageMessageBubble),
            matching: find.byType(Align),
          )
          .first,
    );
    expect(bubble.alignment, Alignment.centerLeft);
    final bubbleContainer = tester.widget<Container>(
      find.descendant(
        of: find.byType(ImageMessageBubble),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).color == Colors.white,
        ),
      ),
    );
    expect((bubbleContainer.decoration! as BoxDecoration).color, Colors.white);
  });

  testWidgets('sender sees their message on the right in a green bubble', (
    tester,
  ) async {
    const message = ChatMessage(
      id: 'message-1',
      senderId: 'user-a',
      text: 'hi',
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatMessageBubble(
            message: message,
            currentUserId: ' user-a ',
            maxWidth: 300,
          ),
        ),
      ),
    );

    final alignment = tester.widget<Align>(
      find.ancestor(of: find.text('hi'), matching: find.byType(Align)).first,
    );
    final bubble = tester.widget<Container>(
      find
          .ancestor(of: find.text('hi'), matching: find.byType(Container))
          .first,
    );
    expect(alignment.alignment, Alignment.centerRight);
    expect(
      (bubble.decoration! as BoxDecoration).color,
      CommunityTheme.bubbleOut,
    );
  });

  testWidgets(
    'recipient sees the sender message on the left in a white bubble',
    (tester) async {
      const message = ChatMessage(
        id: 'message-1',
        senderId: 'user-a',
        text: 'hi',
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChatMessageBubble(
              message: message,
              currentUserId: 'user-b',
              maxWidth: 300,
            ),
          ),
        ),
      );

      final alignment = tester.widget<Align>(
        find.ancestor(of: find.text('hi'), matching: find.byType(Align)).first,
      );
      final bubble = tester.widget<Container>(
        find
            .ancestor(of: find.text('hi'), matching: find.byType(Container))
            .first,
      );
      expect(alignment.alignment, Alignment.centerLeft);
      expect((bubble.decoration! as BoxDecoration).color, Colors.white);
    },
  );

  testWidgets('outgoing message shows its time and blue read ticks', (
    tester,
  ) async {
    final message = ChatMessage(
      id: 'message-read',
      senderId: 'user-a',
      text: 'hello',
      createdAt: DateTime(2026, 1, 2, 13, 5),
      readAt: DateTime(2026, 1, 2, 13, 6),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageBubble(
            message: message,
            currentUserId: 'user-a',
            maxWidth: 300,
          ),
        ),
      ),
    );

    expect(
      find.text(DateFormat.jm().format(message.createdAt!)),
      findsOneWidget,
    );
    final ticks = tester.widget<Icon>(find.byIcon(Icons.done_all_rounded));
    expect(ticks.color, const Color(0xFF34B7F1));
  });

  testWidgets('sent but unread message shows gray double ticks', (
    tester,
  ) async {
    final message = ChatMessage(
      id: 'message-sent',
      senderId: 'user-a',
      text: 'hello',
      createdAt: DateTime(2026, 1, 2, 13, 5),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageBubble(
            message: message,
            currentUserId: 'user-a',
            maxWidth: 300,
          ),
        ),
      ),
    );

    final ticks = tester.widget<Icon>(find.byIcon(Icons.done_all_rounded));
    expect(ticks.color, Colors.grey.shade700);
  });
}
