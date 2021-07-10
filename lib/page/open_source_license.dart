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

import 'package:dan_xi/generated/l10n.dart';
import 'package:dan_xi/page/subpage_main.dart';
import 'package:dan_xi/util/browser_util.dart';
import 'package:dan_xi/util/noticing.dart';
import 'package:dan_xi/widget/platform_app_bar_ex.dart';
import 'package:dan_xi/widget/with_scrollbar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dan_xi/public_extension_methods.dart';

class OpenSourceLicenseList extends StatefulWidget {
  /// 'items': A list of [LicenseItem] to display on the page
  final Map<String, dynamic> arguments;

  const OpenSourceLicenseList({Key key, this.arguments}) : super(key: key);

  @override
  _OpenSourceListState createState() => _OpenSourceListState();
}

class _OpenSourceListState extends State<OpenSourceLicenseList> {
  List<LicenseItem> _items;

  int debugModeEnableStatus = 0;

  @override
  Widget build(BuildContext context) {
    return PlatformScaffold(
      iosContentBottomPadding: true,
      iosContentPadding: true,
      appBar: PlatformAppBarX(
          title: GestureDetector(
        onLongPress: () async {
          if (debugModeEnableStatus++ > 2) {
            SharedPreferences _pref = await SharedPreferences.getInstance();
            if (_pref.containsKey("DEBUG")) {
              Noticing.showNotice(context, "Debug mode disabled");
              _pref.remove("DEBUG");
            } else {
              // Enable debug mode
              Noticing.showNotice(context,
                  "Debug mode enabled. Welcome, developer.\nRefresh for changes to take effect.");
              _pref.setBool("DEBUG",
                  true); // This key either don't exist, or will be true
              RefreshHomepageEvent().fire();
            }
          }
        },
        child: Text(S.of(context).open_source_software_licenses),
      )),
      body: Column(children: [
        Expanded(
            child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: WithScrollbar(
                  child: ListView(
                    controller: PrimaryScrollController.of(context),
                    children: _getListWidgets(),
                  ),
                  controller: PrimaryScrollController.of(context),
                ))),
      ]),
    );
  }

  List<Widget> _getListWidgets() {
    List<Widget> widgets = [];
    if (_items != null)
      _items.forEach((element) {
        widgets.add(Material(
            child: ListTile(
          title: Text(element.name),
          subtitle: Text(element.license.licenseName),
          onTap: () => BrowserUtil.openUrl(element.url, context),
        )));
      });
    return widgets;
  }

  @override
  void initState() {
    super.initState();
    _items = widget.arguments['items'];
  }
}

class License {
  final String licenseName;

  /// unused
  final String licenseText;

  const License(this.licenseName, {this.licenseText});
}

const License LICENSE_APACHE_2_0 = License("Apache License 2.0");
const License LICENSE_BSD = License("BSD License");
const License LICENSE_BSD_3_0_CLAUSE = License("BSD 3-Clause License");
const License LICENSE_LGPL_3_0 =
    License("GNU Lesser General Public License v3.0");
const License LICENSE_GPL_3_0 = License("GNU General Public License v3.0");
const License LICENSE_AGPL_3_0 =
    License("GNU Affero General Public License v3.0");
const License LICENSE_UNLICENSE = License("The Unlicense");
const License LICENSE_MIT = License("MIT License");
const License LICENSE_WTFPL_2_0 = License("WTFPL v2.0");

/// It usually means the author would NOT like to share the open-source project with anyone.
/// Be careful to use it.
const License LICENSE_NO = License("Author claims no specific license");

class LicenseItem {
  /// Name of the repository
  final String name;

  /// License it uses
  final License license;

  /// Url of the repository
  final String url;

  const LicenseItem(this.name, this.license, this.url);
}
