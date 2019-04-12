import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  runApp(MyApp());
}

final ThemeData kIOSTheme = ThemeData(
    primarySwatch: Colors.orange,
    primaryColor: Colors.grey[100],
    primaryColorBrightness: Brightness.light);

final ThemeData kDefaultTheme = ThemeData(
    primarySwatch: Colors.purple, accentColor: Colors.orangeAccent[400]);

final googleSignIn = GoogleSignIn();
final auth = FirebaseAuth.instance;

Future<Null> _ensureLoggedIn() async {
  GoogleSignInAccount user = googleSignIn.currentUser;

  if (user == null) {
    user = await googleSignIn.signInSilently(); // tente login silencioso
  }

  if (user == null) {
    // se não deu certo
    user = await googleSignIn.signIn(); // exibe janela para fazer login
  }

  if (await auth.currentUser() == null) {
    // primeiro autentica no google, e aqui no firebase

    GoogleSignInAuthentication credentials =
        await googleSignIn.currentUser.authentication;

    await auth.signInWithGoogle(
        idToken: credentials.idToken, accessToken: credentials.accessToken);
  }
}

_handleSubmitted(String text) async {
  await _ensureLoggedIn();

  _sendMessage(text: text);
}

void _sendMessage({String text, String imgUrl}) {
  Firestore.instance
      .collection("messages")
      .add({
        "text": text,
        "imgUrl": imgUrl,
        "senderName": googleSignIn.currentUser.displayName,
        "senderPhotoUrl": googleSignIn.currentUser.photoUrl
      });
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Chat app", // para mostrar na terefa
      debugShowCheckedModeBanner: false,
      theme: Theme.of(context).platform == TargetPlatform.iOS
          ? // definindo o tema conforme a plataforma
          kIOSTheme
          : kDefaultTheme,
      home: ChatScreen(),
    );
  }
}

Future<Null> _sendImg(File imgFile) async {

  StorageUploadTask task = FirebaseStorage.instance.ref()
  .child("photos")// pasta
  .child(
    googleSignIn.currentUser.id.toString()+
      DateTime.now().millisecondsSinceEpoch.toString()
  ).putFile(imgFile);// pega a referencia do storege, seta o nome para a imagem

  StorageTaskSnapshot taskSnapshot = await task.onComplete;
  String url = await taskSnapshot.ref.getDownloadURL();
  _sendMessage(imgUrl: url);

}

class ChatScreen extends StatefulWidget {
  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
        // para igonorar algumas coisas do iphone
        bottom: false,
        top: false, // nao vai ignorar
        child: Scaffold(
          appBar: AppBar(
            title: Text("Chat App"),
            centerTitle: true,
            elevation:
                Theme.of(context).platform == TargetPlatform.iOS ? 0.0 : 4.0,
          ),
          body: Column(
            children: <Widget>[
              Expanded(
                child: StreamBuilder(// para refazer a área caso tenha alteração de dados
                  stream: Firestore.instance.collection("messages").snapshots(),
                  builder: (context, snapshot){
                    switch(snapshot.connectionState){
                      case ConnectionState.waiting:
                      case ConnectionState.none:
                        return Center(
                          child: CircularProgressIndicator(),
                        );
                      default:
                        return ListView.builder(
                          reverse: true, // para as mensages aparecerem em baixo
                          itemCount: snapshot.data.documents.length,
                          itemBuilder: (context, index){

                            List l = snapshot.data.documents.reversed.toList();
                            return ChatMessage(l[index].data);
                          },
                        );
                    }
                  }
                ),
              ),
              Divider(
                height: 1.0,
              ),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                ),
                child: TextComposer(),
              ),
            ],
          ),
        ));
  }
}

class TextComposer extends StatefulWidget {
  @override
  _TextComposerState createState() => _TextComposerState();
}

class _TextComposerState extends State<TextComposer> {
  bool _isComposing = false;
  final _textController = TextEditingController();

  void _reset(){
    _textController.clear();
    setState(() {
      _isComposing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return IconTheme(
      // para especificar a cor dos icones
      data: IconThemeData(color: Theme.of(context).accentColor),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8.0),
        // coloca dos dois lados
        decoration: (Theme.of(context).platform == TargetPlatform.iOS
            ? BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey[200])))
            : null),
        child: Row(
          children: <Widget>[
            Container(
              child:
                  IconButton(
                      icon: Icon(Icons.photo_camera),
                      onPressed: () async {
                        await _ensureLoggedIn();
                        File imgFile = await ImagePicker.pickImage(source: ImageSource.camera);

                        if(imgFile == null) return ;

                        _sendImg(imgFile);

                      }
                  ),
            ),
            Expanded(
              child: TextField(
                controller: _textController,
                decoration:
                    InputDecoration.collapsed(hintText: "Enviar uma Mensagem"),
                onChanged: (text) {
                  setState(() {
                    // para habilitar ou não o botao de enviar
                    _isComposing = text.length > 0;
                  });
                },
                onSubmitted: (text) {
                  // para enviar pelo botao do teclado
                  _handleSubmitted(text);
                  _reset();
                },
              ),
            ),
            Container(
                margin: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Theme.of(context).platform == TargetPlatform.iOS
                    ? CupertinoButton(
                        child: Text("Enviar"),
                        onPressed: _isComposing
                            ? () {
                                _handleSubmitted(_textController.text);
                                _reset();
                              }
                            : null // desabilita o botao
                        )
                    : IconButton(
                        icon: Icon(Icons.send),
                        onPressed: _isComposing
                            ? () {
                                _handleSubmitted(_textController.text);
                                _reset();
                              }
                            : null) // desabilita o botao
                ),
          ],
        ),
      ),
    );
  }
}

class ChatMessage extends StatelessWidget {

  final Map<String, dynamic> data;

  ChatMessage(this.data);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            margin: const EdgeInsets.only(right: 16.0),
            child: CircleAvatar(
              backgroundImage: NetworkImage(
                  data["senderPhotoUrl"]
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  data["senderName"],
                  style: Theme.of(context).textTheme.subhead,
                ),
                Container(
                  margin: EdgeInsets.only(top: 5.0),
                  child: data["imgUrl"] != null ?
                      Image.network(
                        data["imgUrl"],
                        width: 250.0,
                      )
                      :
                      Text(data["text"])
                  ,
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}
