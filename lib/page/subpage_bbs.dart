/*
 *     Copyright (C) 2021  DanXi-Dev
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version.
 *
 *     This program is distributed in the hope that it will be useful,
 *     but WITHOUT ANY WARRANTY; without even the implied warranty of
 *     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *     GNU General Public License for more details.
 *
 *     You should have received a copy of the GNU General Public License
 *     along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:async';
import 'dart:io';

import 'package:beautifulsoup/beautifulsoup.dart';
import 'package:dan_xi/common/constant.dart';
import 'package:dan_xi/common/feature_registers.dart';
import 'package:dan_xi/generated/l10n.dart';
import 'package:dan_xi/master_detail/master_detail_view.dart';
import 'package:dan_xi/model/person.dart';
import 'package:dan_xi/model/post.dart';
import 'package:dan_xi/page/platform_subpage.dart';
import 'package:dan_xi/provider/settings_provider.dart';
import 'package:dan_xi/public_extension_methods.dart';
import 'package:dan_xi/repository/bbs/post_repository.dart';
import 'package:dan_xi/util/browser_util.dart';
import 'package:dan_xi/util/human_duration.dart';
import 'package:dan_xi/util/noticing.dart';
import 'package:dan_xi/util/stream_listener.dart';
import 'package:dan_xi/widget/bbs_editor.dart';
import 'package:dan_xi/widget/future_widget.dart';
import 'package:dan_xi/widget/platform_app_bar_ex.dart';
import 'package:dan_xi/widget/round_chip.dart';
import 'package:dan_xi/widget/with_scrollbar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:flutter_progress_dialog/flutter_progress_dialog.dart';
import 'package:flutter_progress_dialog/src/progress_dialog.dart';
import 'package:flutter_sfsymbols/flutter_sfsymbols.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';

const kCompatibleUserGroup = [
  UserGroup.FUDAN_STUDENT,
  UserGroup.FUDAN_STAFF,
  UserGroup.SJTU_STUDENT
];

bool isHtml(String content) {
  var htmlMatcher = RegExp(r'<.+>.*</.+>', dotAll: true);
  return htmlMatcher.hasMatch(content);
}

/// Render the text from a clip of [content].
/// Also supports adding image tag to markdown posts
String renderText(String content, String imagePlaceholder) {
  if (!isHtml(content)) {
    content = md.markdownToHtml(content);
  }
  // Deal with Markdown
  content =
      content.replaceAll(RegExp(r"!\[.*\]\(http(s)?://.+\)"), imagePlaceholder);

  var soup = Beautifulsoup(content);
  var images = soup.find_all("img");
  if (images.length > 0) return soup.get_text().trim() + imagePlaceholder;
  return soup.get_text().trim();
}

const String KEY_NO_TAG = "默认";

/// Turn tags into Widgets
Widget generateTagWidgets(BBSPost e, void Function(String) onTap) {
  if (e == null || e.tag == null) return Container();
  List<Widget> _tags = [];
  e.tag.forEach((element) {
    if (element.name == KEY_NO_TAG) return [Container()];
    _tags.add(Flex(
        direction: Axis.horizontal,
        mainAxisSize: MainAxisSize.min,
        children: [
          RoundChip(
            onTap: () => onTap(element.name),
            label: element.name,
            color: Constant.getColorFromString(element.color),
          ),
        ]));
  });
  return Wrap(
    direction: Axis.horizontal,
    spacing: 4,
    runSpacing: 4,
    children: _tags,
  );
}

class BBSSubpage extends PlatformSubpage {
  @override
  bool get needPadding => true;

  final Map<String, dynamic> arguments;

  @override
  _BBSSubpageState createState() => _BBSSubpageState();

  BBSSubpage({Key key, this.arguments});
}

class AddNewPostEvent {}

class RetrieveNewPostEvent {}

class SortOrderChangedEvent {
  SortOrder newOrder;

  SortOrderChangedEvent(this.newOrder);
}

/// A list page showing bbs posts.
///
/// Arguments:
/// [bool] showFavoredDiscussion: if [showFavoredDiscussion] is not null,
/// it means this page is showing user's favored posts.
/// [String] tagFilter: if [tagFilter] is not null, it means this page is showing
/// the posts which is tagged with [tagFilter].
///
class _BBSSubpageState extends State<BBSSubpage>
    with AutomaticKeepAliveClientMixin {
  /// Unrelated to the state.
  /// These field should only be initialized once when created.
  final StateStreamListener _postSubscription = StateStreamListener();
  final StateStreamListener _refreshSubscription = StateStreamListener();
  final StateStreamListener _searchSubscription = StateStreamListener();
  final StateStreamListener _sortOrderChangedSubscription =
      StateStreamListener();
  SharedPreferences _preferences;
  String _tagFilter;
  FocusNode _searchFocus = FocusNode();

  /// Fields related to the display states.
  int _currentBBSPage;
  SortOrder _sortOrder;
  bool _isRefreshing;
  bool _isEndIndicatorShown;
  FoldBehavior _foldBehavior;

  /// This is to prevent the entire thing being rebuilt on iOS when the keyboard pops
  bool _fieldInitComplete;

  /// These field holds the content on the page.
  List<Widget> _lastPageItems;
  AsyncSnapshot _lastSnapshotData;

  /// Future of network loading.
  Future _contentFuture;

  ///Set the Future of the page to a single variable so that when the framework calls build(), the content is not reloaded every time.
  void _setContent() {
    if (checkGroupByContext(kCompatibleUserGroup, context)) {
      _sortOrder = SettingsProvider.of(_preferences).fduholeSortOrder ??
          SortOrder.LAST_REPLIED;
      _foldBehavior = SettingsProvider.of(_preferences).fduholeFoldBehavior ??
          FoldBehavior.FOLD;
      if (_tagFilter != null)
        _contentFuture = PostRepository.getInstance()
            .loadTagFilteredPosts(_tagFilter, _sortOrder);
      else if (widget.arguments != null &&
          widget.arguments.containsKey('showFavoredDiscussion'))
        _contentFuture = PostRepository.getInstance().getFavoredDiscussions();
      else
        _contentFuture = loginAndLoadPost(context.personInfo, _sortOrder);
    } else {
      _contentFuture =
          Future<List<BBSPost>>.error(NotLoginError("Logged in as Visitor."));
    }
  }

  void refreshSelf() {
    if (mounted) {
      // ignore: invalid_use_of_protected_member
      setState(() {
        _initialize();
        _setContent();
      });
    }
  }

  void _initialize() {
    _currentBBSPage = 1;
    _lastPageItems = [];
    _lastSnapshotData = null;
    _isRefreshing = true;
    _isEndIndicatorShown = false;
  }

  Widget _buildSearchTextField() {
    // If user is filtering by tag, do not build search text field.
    if (_tagFilter != null) return Container();

    return Container(
      color: Theme.of(context).canvasColor,
      padding: Theme.of(context)
          .cardTheme
          .margin, //EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: CupertinoSearchTextField(
        focusNode: _searchFocus,
        placeholder: S.of(context).search_hint,
        onSubmitted: (value) {
          value = value.trim();
          if (value.isEmpty) return;
          // Determine if user is using #PID pattern to reach a specific post
          RegExp pidPattern = new RegExp(r'#[0-9]+');
          if (value.startsWith(pidPattern)) {
            // We needn't deal with the situation that "id = null" here.
            // If so, it will turn into a 404 http error.
            _goToPIDResultPage(
                int.tryParse(pidPattern.firstMatch(value)[0].substring(1)));
          } else
            smartNavigatorPush(context, "/bbs/postDetail", arguments: {
              "post": PostRepository.getInstance().loadSearchResults(value)
            });
        },
      ),
    );
  }

  _goToPIDResultPage(int pid) async {
    ProgressFuture progressDialog = showProgressDialog(
        loadingText: S.of(context).loading, context: context);
    final BBSPost post = await PostRepository.getInstance()
        .loadSpecificPost(pid)
        .onError((error, stackTrace) {
      if (error.response?.statusCode == HttpStatus.notFound)
        Noticing.showNotice(context, S.of(context).post_does_not_exist,
            title: S.of(context).fatal_error);
      else
        Noticing.showNotice(context, error.toString(),
            title: S.of(context).fatal_error);
      progressDialog.dismiss();
      return null;
    });
    if (post != null)
      smartNavigatorPush(context, "/bbs/postDetail", arguments: {
        "post": post,
      });
    progressDialog.dismiss();
  }

  @override
  void initState() {
    super.initState();
    _fieldInitComplete = false;
    _initialize();
    _postSubscription.bindOnlyInvalid(
        Constant.eventBus.on<AddNewPostEvent>().listen((_) async {
          final bool success = await BBSEditor.createNewPost(context);
          if (success) refreshSelf();
        }),
        hashCode);
    _refreshSubscription.bindOnlyInvalid(
        Constant.eventBus
            .on<RetrieveNewPostEvent>()
            .listen((_) => refreshSelf()),
        hashCode);
    _sortOrderChangedSubscription.bindOnlyInvalid(
        Constant.eventBus.on<SortOrderChangedEvent>().listen((event) {
          SettingsProvider.of(_preferences).fduholeSortOrder =
              _sortOrder = event.newOrder;
          refreshSelf();
        }),
        hashCode);
  }

  @override
  void didChangeDependencies() {
    if (!_fieldInitComplete) {
      if (widget.arguments != null && widget.arguments.containsKey('tagFilter'))
        _tagFilter = widget.arguments['tagFilter'];
      if (widget.arguments != null &&
          widget.arguments.containsKey('preferences'))
        _preferences = widget.arguments['preferences'];
      else
        _preferences = Provider.of<SharedPreferences>(context);
      _setContent();
      _fieldInitComplete = true;
    }
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    super.dispose();
    _postSubscription.cancel();
    _refreshSubscription.cancel();
    _searchSubscription.cancel();
    _sortOrderChangedSubscription.cancel();
  }

  /// Log in and load all of the posts.
  Future<List<BBSPost>> loginAndLoadPost(
      PersonInfo info, SortOrder sortOrder) async {
    if (!PostRepository.getInstance().isUserInitialized)
      await PostRepository.getInstance().initializeUser(info, _preferences);
    return await PostRepository.getInstance()
        .loadPosts(_currentBBSPage, sortOrder);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_lastPageItems.isEmpty) _lastPageItems = [_buildSearchTextField()];
    if (widget.arguments == null)
      return _buildPageBody();
    else if (widget.arguments.containsKey('showFavoredDiscussion')) {
      return PlatformScaffold(
        iosContentPadding: true,
        iosContentBottomPadding: false,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: PlatformAppBarX(
          title: Text(S.of(context).favorites),
        ),
        body: _buildPageBody(),
      );
    }
    return PlatformScaffold(
      iosContentPadding: true,
      iosContentBottomPadding: false,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: PlatformAppBarX(
        title: Text(S.of(context).filtering_by_tag(_tagFilter)),
      ),
      body: _buildPageBody(),
    );
  }

  Widget _buildPageBody() {
    return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: (_) {
          if (_searchFocus.hasFocus) _searchFocus.unfocus();
        },
        child: RefreshIndicator(
            color: Theme.of(context).accentColor,
            backgroundColor: Theme.of(context).dialogBackgroundColor,
            onRefresh: () async {
              HapticFeedback.mediumImpact();
              refreshSelf();
            },
            child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: FutureWidget<List<BBSPost>>(
                    future: _contentFuture,
                    successBuilder: (BuildContext context,
                        AsyncSnapshot<List<BBSPost>> snapshot) {
                      // Handle Empty Favorites
                      if (widget.arguments != null &&
                          widget.arguments
                              .containsKey('showFavoredDiscussion') &&
                          snapshot.data.isEmpty) {
                        return _buildEmptyFavoritesPage();
                      }

                      if ((_lastSnapshotData?.data?.isEmpty ?? true) ||
                          snapshot.data.isEmpty ||
                          _lastSnapshotData.data.last.id !=
                              snapshot.data.last.id)
                        snapshot.data.forEach((element) {
                          _lastPageItems.add(_buildListItem(element));
                        });
                      _isRefreshing = false;
                      _lastSnapshotData = snapshot;
                      return _buildPage(snapshot.data, false);
                    },
                    errorBuilder: (BuildContext context,
                        AsyncSnapshot<List<BBSPost>> snapshot) {
                      if (snapshot.error is LoginExpiredError) {
                        SettingsProvider.of(_preferences)
                            .deleteSavedFduholeToken();
                        return _buildErrorPage(
                            error: S.of(context).error_login_expired);
                      } else if (snapshot.error is NotLoginError)
                        return _buildErrorPage(
                            error:
                                (snapshot.error as NotLoginError).errorMessage);
                      return _buildErrorPage(error: snapshot.error.toString());
                    },
                    loadingBuilder: () {
                      _isRefreshing = true;
                      if (_lastSnapshotData == null)
                        return Container(
                          padding: EdgeInsets.all(8),
                          child: Center(
                            child: PlatformCircularProgressIndicator(),
                          ),
                        );
                      return _buildPage(_lastSnapshotData.data, true);
                    }))));
  }

  Widget _buildLoadingPage() => Container(
        padding: EdgeInsets.all(8),
        child: Center(child: PlatformCircularProgressIndicator()),
      );

  Widget _buildEmptyFavoritesPage() => Container(
        padding: EdgeInsets.all(8),
        child: Center(child: Text(S.of(context).no_favorites)),
      );

  Widget _buildErrorPage({String error}) {
    return GestureDetector(
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 48),
          child: Text(
            S.of(context).failed + '\n\nThe error was:\n' + error,
          ),
        ),
      ),
      onTap: () {
        refreshSelf();
      },
    );
    //  ],);
  }

  Widget _buildPage(List<BBSPost> data, bool isLoading) {
    NotificationListenerCallback<ScrollNotification> scrollToEnd =
        (ScrollNotification scrollInfo) {
      if (_tagFilter == null &&
          scrollInfo.metrics.extentAfter < 500 &&
          !_isRefreshing &&
          !_isEndIndicatorShown) {
        _isRefreshing = true;
        setState(() {
          _currentBBSPage++;
          _setContent();
        });
      }
      return false;
    };
    return NotificationListener<ScrollNotification>(
      child: WithScrollbar(
        child: ListView.builder(
          primary: true,
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: (_currentBBSPage) * Constant.POST_COUNT_PER_PAGE +
              (isLoading ? 1 - Constant.POST_COUNT_PER_PAGE : 0),
          itemBuilder: (context, index) => _getListItemAt(index, data),
        ),
        controller: PrimaryScrollController.of(context),
      ),
      onNotification: scrollToEnd,
    );
  }

  Widget _getListItemAt(int index, List<BBSPost> data) {
    if (!_isEndIndicatorShown &&
        !_isRefreshing &&
        index >= _lastPageItems.length) {
      _isEndIndicatorShown = true;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(S.of(context).end_reached),
          )
        ],
      );
    }
    if (index >= _lastPageItems.length)
      return _isEndIndicatorShown ? Container() : _buildLoadingPage();
    return _lastPageItems[index];
  }

  _launchUrlWithNotice(LinkableElement link) async {
    if (await canLaunch(link.url)) {
      BrowserUtil.openUrl(link.url, context);
    } else {
      Noticing.showNotice(context, S.of(context).cannot_launch_url);
    }
  }

  Widget _buildListItem(BBSPost postElement) {
    if (_foldBehavior == FoldBehavior.HIDE && postElement.is_folded)
      return Container();
    Linkify postContentWidget = Linkify(
      text: renderText(postElement.first_post.content, S.of(context).image_tag),
      style: TextStyle(fontSize: 16),
      maxLines: 6,
      overflow: TextOverflow.ellipsis,
      onOpen: _launchUrlWithNotice,
    );
    TextStyle infoStyle =
        TextStyle(color: Theme.of(context).hintColor, fontSize: 12);
    String lastReplyContent =
        renderText(postElement.last_post.content, S.of(context).image_tag);
    return Material(
      child: Card(
          child: Column(children: [
        ListTile(
            contentPadding: EdgeInsets.fromLTRB(16, 4, 10, 0),
            dense: false,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                generateTagWidgets(postElement, (String tagname) {
                  smartNavigatorPush(context, '/bbs/discussions', arguments: {
                    "tagFilter": tagname,
                    'preferences': _preferences,
                  });
                }),
                const SizedBox(
                  height: 10,
                ),
                (postElement.is_folded && _foldBehavior == FoldBehavior.FOLD)
                    ? Theme(
                        data: Theme.of(context)
                            .copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          expandedCrossAxisAlignment: CrossAxisAlignment.start,
                          expandedAlignment: Alignment.topLeft,
                          childrenPadding: EdgeInsets.symmetric(vertical: 4),
                          tilePadding: EdgeInsets.zero,
                          title: Text(
                            S.of(context).folded,
                            style: infoStyle,
                          ),
                          children: [postContentWidget],
                        ),
                      )
                    : postContentWidget,
              ],
            ),
            subtitle: Column(
              children: [
                const SizedBox(
                  height: 12,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "#${postElement.id}",
                      style: infoStyle,
                    ),
                    Text(
                      HumanDuration.format(
                          context, DateTime.parse(postElement.date_created)),
                      style: infoStyle,
                    ),
                    Row(
                      children: [
                        Text(
                          "${postElement.count} ",
                          style: infoStyle,
                        ),
                        Icon(
                          SFSymbols.ellipses_bubble,
                          size: infoStyle.fontSize,
                          color: infoStyle.color,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            onTap: () {
              smartNavigatorPush(context, "/bbs/postDetail", arguments: {
                "post": postElement,
              });
            }),
        if (!(postElement.is_folded && _foldBehavior == FoldBehavior.FOLD) &&
            postElement.last_post.id != postElement.first_post.id)
          Divider(
            height: 4,
          ),
        if (!(postElement.is_folded && _foldBehavior == FoldBehavior.FOLD) &&
            postElement.last_post.id != postElement.first_post.id)
          //_buildCommentView(postElement),
          ListTile(
              dense: true,
              minLeadingWidth: 16,
              leading: Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Icon(
                  SFSymbols.quote_bubble,
                  color: Theme.of(context).hintColor,
                ),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(0, 8, 0, 4),
                    child: Text(
                      S.of(context).latest_reply(
                          postElement.last_post.username,
                          HumanDuration.format(
                              context,
                              DateTime.parse(
                                  postElement.last_post.date_created))),
                      style: TextStyle(color: Theme.of(context).hintColor),
                    ),
                  ),
                  Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Linkify(
                          text: lastReplyContent.trim().isEmpty
                              ? S.of(context).no_summary
                              : lastReplyContent,
                          style: TextStyle(fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          onOpen: _launchUrlWithNotice)),
                ],
              ),
              onTap: () =>
                  smartNavigatorPush(context, "/bbs/postDetail", arguments: {
                    "post": postElement,
                    "scroll_to_end": true,
                  }))
      ])),
    );
  }



  @override
  bool get wantKeepAlive => true;
}
