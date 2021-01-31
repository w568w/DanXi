import 'package:data_plugin/bmob/bmob_query.dart';
import 'package:data_plugin/bmob/table/bmob_object.dart';
import 'package:json_annotation/json_annotation.dart';

part 'post.g.dart';

@JsonSerializable()
class BBSPost extends BmobObject {
  String __type = "BBSPost";

  //replyPost = "0" when it's the first floor of a post
  //replyTo = "0" when it's a reply to nobody
  String title, author, content, replyPost = "0", replyTo = "0";

  factory BBSPost.fromJson(Map<String, dynamic> json) =>
      _$BBSPostFromJson(json);

  Map<String, dynamic> toJson() => _$BBSPostToJson(this);

  BBSPost(this.title, this.author, this.content, this.replyPost, this.replyTo);

  BBSPost.newReply(this.author, this.content, this.replyPost, {this.replyTo});

  BBSPost.newPost(this.author, this.content);

  // ignore: non_constant_identifier_names
  static BmobQuery get QUERY_ALL_POST => BmobQuery<BBSPost>()
      .addWhereEqualTo("replyPost", "0")
      .setOrder("-createdAt");

  @override
  Map getParams() => {
        "author": author,
        "content": content,
        "replyPost": replyPost,
        "replyTo": replyTo
      };
}