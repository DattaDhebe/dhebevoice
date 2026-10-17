import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A searchable, lazily built list that initially centers the selected entry.
class ReaderListSheet<T> extends StatefulWidget {
  const ReaderListSheet({
    super.key,
    required this.title,
    required this.items,
    required this.searchText,
    required this.itemBuilder,
    this.selectedIndex = -1,
    this.itemExtent = 104,
    this.emptyMessage = 'Nothing here yet.',
    this.searchHint = 'Search',
  });

  final String title;
  final List<T> items;
  final String Function(T item, int index) searchText;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final int selectedIndex;
  final double itemExtent;
  final String emptyMessage;
  final String searchHint;

  @override
  State<ReaderListSheet<T>> createState() => _ReaderListSheetState<T>();
}

class _ReaderListSheetState<T> extends State<ReaderListSheet<T>> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  var _query = '';
  var _scheduledInitialScroll = false;
  List<String> _searchIndex = const [];
  List<int> _filteredIndices = const [];

  @override
  void initState() {
    super.initState();
    _indexItems();
  }

  @override
  void didUpdateWidget(covariant ReaderListSheet<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.items, widget.items)) _indexItems();
  }

  void _indexItems() {
    _searchIndex = List.generate(
      widget.items.length,
      (index) => widget.searchText(widget.items[index], index).toLowerCase(),
      growable: false,
    );
    _filterItems();
  }

  void _filterItems() {
    _filteredIndices = _query.isEmpty
        ? const []
        : [
            for (var index = 0; index < _searchIndex.length; index++)
              if (_searchIndex[index].contains(_query)) index,
          ];
  }

  void _updateQuery(String value) {
    setState(() {
      _query = value.trim().toLowerCase();
      _filterItems();
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final itemExtent =
        widget.itemExtent * media.textScaler.scale(1).clamp(1, 2.5);
    final itemCount = _query.isEmpty
        ? widget.items.length
        : _filteredIndices.length;
    if (!_scheduledInitialScroll) {
      _scheduledInitialScroll = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _query.isNotEmpty) {
          return;
        }
        if (!_scrollController.hasClients) {
          _scheduledInitialScroll = false;
          return;
        }
        final position = _scrollController.position;
        final offset =
            widget.selectedIndex * itemExtent -
            (position.viewportDimension - itemExtent) / 2;
        _scrollController.jumpTo(offset.clamp(0.0, position.maxScrollExtent));
      });
    }

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: math.max(
            200,
            (media.size.height - media.viewInsets.bottom - media.padding.top) *
                0.85,
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: widget.searchHint,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _searchController.clear();
                              _updateQuery('');
                            },
                          ),
                  ),
                  onChanged: _updateQuery,
                ),
              ),
              Expanded(
                child: itemCount == 0
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _query.isEmpty
                                ? widget.emptyMessage
                                : 'No matching results.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemExtent: itemExtent,
                        itemCount: itemCount,
                        itemBuilder: (context, index) {
                          final originalIndex = _query.isEmpty
                              ? index
                              : _filteredIndices[index];
                          return widget.itemBuilder(
                            context,
                            widget.items[originalIndex],
                            originalIndex,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
