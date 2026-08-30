import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/concurrency/stale_write.dart';
import '../../data/models/storefront_config.dart';
import '../../data/repositories/storefront_repository.dart';

enum StorefrontPricePreviewMode {
  basePrice('السعر الأساسي'),
  customerPreview('معاينة كعميل');

  const StorefrontPricePreviewMode(this.labelAr);

  final String labelAr;
}

enum StorefrontPreviewDevice {
  phone(390, 'هاتف'),
  desktop(1200, 'سطح المكتب');

  const StorefrontPreviewDevice(this.width, this.labelAr);

  final double width;
  final String labelAr;
}

enum StorefrontBuilderTab {
  preview('معاينة'),
  sections('الأقسام'),
  design('التصميم');

  const StorefrontBuilderTab(this.labelAr);

  final String labelAr;
}

enum StorefrontSidebarMode {
  sections('الأقسام'),
  design('التصميم'),
  page('الصفحة');

  const StorefrontSidebarMode(this.labelAr);

  final String labelAr;
}

enum StorefrontDraftSyncStatus {
  idle,
  pending,
  saving,
  saved,
  error,
}

class StorefrontBuilderState {
  StorefrontBuilderState({
    this.loading = true,
    this.saving = false,
    this.publishing = false,
    StorefrontConfig? draft,
    StorefrontConfig? published,
    this.updatedAt,
    this.publishedAt,
    this.hasUnsavedChanges = false,
    this.syncStatus = StorefrontDraftSyncStatus.idle,
    this.previewPublished = false,
    this.selectedSection,
    this.previewDevice = StorefrontPreviewDevice.phone,
    this.pricePreviewMode = StorefrontPricePreviewMode.basePrice,
    this.previewCustomerId,
    this.errorMessage,
    this.staleWrite = false,
    this.mobileTab = StorefrontBuilderTab.preview,
    this.sidebarMode = StorefrontSidebarMode.sections,
    this.sidebarCollapsed = false,
    this.inspectorCollapsed = false,
  })  : draft = draft ?? StorefrontDefaults.bundled,
        published = published ?? StorefrontDefaults.bundled;

  final bool loading;
  final bool saving;
  final bool publishing;
  final StorefrontConfig draft;
  final StorefrontConfig published;
  final DateTime? updatedAt;
  final DateTime? publishedAt;
  final bool hasUnsavedChanges;
  final StorefrontDraftSyncStatus syncStatus;
  final bool previewPublished;
  final StorefrontSectionType? selectedSection;
  final StorefrontPreviewDevice previewDevice;
  final StorefrontPricePreviewMode pricePreviewMode;
  final String? previewCustomerId;
  final String? errorMessage;
  final bool staleWrite;
  final StorefrontBuilderTab mobileTab;
  final StorefrontSidebarMode sidebarMode;
  final bool sidebarCollapsed;
  final bool inspectorCollapsed;

  StorefrontConfig get activeConfig => previewPublished ? published : draft;

  bool get hasUnpublishedChanges => draft.encode() != published.encode();

  String get draftStatusLabelAr {
    if (saving || syncStatus == StorefrontDraftSyncStatus.saving) {
      return 'جاري الحفظ…';
    }
    if (syncStatus == StorefrontDraftSyncStatus.error) {
      return 'خطأ في الحفظ';
    }
    if (hasUnsavedChanges ||
        syncStatus == StorefrontDraftSyncStatus.pending) {
      return 'مسودة غير محفوظة';
    }
    if (hasUnpublishedChanges) {
      return 'مسودة محفوظة — غير منشورة';
    }
    if (syncStatus == StorefrontDraftSyncStatus.saved) {
      return 'تم الحفظ';
    }
    return 'منشور ومحدّث';
  }

  StorefrontBuilderState copyWith({
    bool? loading,
    bool? saving,
    bool? publishing,
    StorefrontConfig? draft,
    StorefrontConfig? published,
    DateTime? updatedAt,
    DateTime? publishedAt,
    bool? hasUnsavedChanges,
    StorefrontDraftSyncStatus? syncStatus,
    bool? previewPublished,
    StorefrontSectionType? selectedSection,
    bool clearSelectedSection = false,
    StorefrontPreviewDevice? previewDevice,
    StorefrontPricePreviewMode? pricePreviewMode,
    String? previewCustomerId,
    String? errorMessage,
    bool clearError = false,
    bool? staleWrite,
    StorefrontBuilderTab? mobileTab,
    StorefrontSidebarMode? sidebarMode,
    bool? sidebarCollapsed,
    bool? inspectorCollapsed,
  }) {
    return StorefrontBuilderState(
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      publishing: publishing ?? this.publishing,
      draft: draft ?? this.draft,
      published: published ?? this.published,
      updatedAt: updatedAt ?? this.updatedAt,
      publishedAt: publishedAt ?? this.publishedAt,
      hasUnsavedChanges: hasUnsavedChanges ?? this.hasUnsavedChanges,
      syncStatus: syncStatus ?? this.syncStatus,
      previewPublished: previewPublished ?? this.previewPublished,
      selectedSection:
          clearSelectedSection ? null : selectedSection ?? this.selectedSection,
      previewDevice: previewDevice ?? this.previewDevice,
      pricePreviewMode: pricePreviewMode ?? this.pricePreviewMode,
      previewCustomerId: previewCustomerId ?? this.previewCustomerId,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      staleWrite: clearError ? false : (staleWrite ?? this.staleWrite),
      mobileTab: mobileTab ?? this.mobileTab,
      sidebarMode: sidebarMode ?? this.sidebarMode,
      sidebarCollapsed: sidebarCollapsed ?? this.sidebarCollapsed,
      inspectorCollapsed: inspectorCollapsed ?? this.inspectorCollapsed,
    );
  }
}

final adminStorefrontControllerProvider =
    StateNotifierProvider<AdminStorefrontController, StorefrontBuilderState>(
  (ref) => AdminStorefrontController(ref.watch(storefrontRepositoryProvider)),
);

class AdminStorefrontController extends StateNotifier<StorefrontBuilderState> {
  AdminStorefrontController(this._repository, {bool autoLoad = true})
      : super(StorefrontBuilderState()) {
    if (autoLoad) load();
  }

  static const maxHistory = 40;
  static const autosaveDelay = Duration(milliseconds: 600);

  final StorefrontRepository _repository;
  final ListQueue<StorefrontConfig> _undo = ListQueue();
  final ListQueue<StorefrontConfig> _redo = ListQueue();
  StorefrontConfig? _savedDraft;
  Timer? _autosaveTimer;
  int _autosaveGeneration = 0;
  Future<bool>? _inFlightSave;

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    _autosaveTimer?.cancel();
    state = state.copyWith(loading: true, clearError: true);
    try {
      final adminState = await _repository.loadAdminState();
      _savedDraft = adminState.draftConfig;
      _undo.clear();
      _redo.clear();
      state = state.copyWith(
        loading: false,
        draft: adminState.draftConfig,
        published: adminState.publishedConfig,
        updatedAt: adminState.updatedAt,
        publishedAt: adminState.publishedAt,
        hasUnsavedChanges: false,
        syncStatus: StorefrontDraftSyncStatus.idle,
        previewPublished: false,
        selectedSection: adminState.draftConfig.sections.first.type,
      );
    } catch (error) {
      state = state.copyWith(
        loading: false,
        syncStatus: StorefrontDraftSyncStatus.error,
        errorMessage: error.toString(),
      );
    }
  }

  void _pushHistory(StorefrontConfig before) {
    _undo.addLast(before);
    if (_undo.length > maxHistory) _undo.removeFirst();
    _redo.clear();
  }

  void _applyDraft(StorefrontConfig next, {bool trackHistory = true}) {
    if (trackHistory) _pushHistory(state.draft);
    final dirty = next.encode() != (_savedDraft?.encode() ?? '');
    state = state.copyWith(
      draft: next,
      hasUnsavedChanges: dirty,
      syncStatus: dirty
          ? StorefrontDraftSyncStatus.pending
          : StorefrontDraftSyncStatus.idle,
      previewPublished: false,
      clearError: true,
    );
    if (dirty) {
      _scheduleAutosave();
    } else {
      _autosaveTimer?.cancel();
    }
  }

  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    final generation = ++_autosaveGeneration;
    _autosaveTimer = Timer(autosaveDelay, () {
      if (generation != _autosaveGeneration) return;
      unawaited(saveDraft(fromAutosave: true));
    });
  }

  /// Cancels the debounce timer and persists immediately (e.g. color picker done).
  Future<bool> flushAutosave() async {
    _autosaveTimer?.cancel();
    if (!state.hasUnsavedChanges) return true;
    return saveDraft(fromAutosave: true);
  }

  void selectSection(StorefrontSectionType type) {
    state = state.copyWith(selectedSection: type);
  }

  void setMobileTab(StorefrontBuilderTab tab) {
    state = state.copyWith(mobileTab: tab);
  }

  void setSidebarMode(StorefrontSidebarMode mode) {
    state = state.copyWith(sidebarMode: mode);
  }

  void toggleSidebarCollapsed() {
    state = state.copyWith(sidebarCollapsed: !state.sidebarCollapsed);
  }

  void toggleInspectorCollapsed() {
    state = state.copyWith(inspectorCollapsed: !state.inspectorCollapsed);
  }

  void togglePreviewPublished(bool value) {
    state = state.copyWith(previewPublished: value);
  }

  void setPreviewDevice(StorefrontPreviewDevice device) {
    state = state.copyWith(previewDevice: device);
  }

  void setPricePreviewMode(StorefrontPricePreviewMode mode) {
    state = state.copyWith(pricePreviewMode: mode);
  }

  void setPreviewCustomerId(String? customerId) {
    state = state.copyWith(previewCustomerId: customerId);
  }

  void reorderSection(int oldIndex, int newIndex) {
    final sections = [...state.draft.sections];
    if (oldIndex < 0 ||
        newIndex < 0 ||
        oldIndex >= sections.length ||
        newIndex >= sections.length) {
      return;
    }
    final item = sections.removeAt(oldIndex);
    sections.insert(newIndex, item);
    _applyDraft(state.draft.copyWith(sections: sections));
    state = state.copyWith(selectedSection: item.type);
  }

  void moveSectionUp(StorefrontSectionType type) {
    final sections = [...state.draft.sections];
    final index = sections.indexWhere((s) => s.type == type);
    if (index <= 0) return;
    reorderSection(index, index - 1);
  }

  void moveSectionDown(StorefrontSectionType type) {
    final sections = [...state.draft.sections];
    final index = sections.indexWhere((s) => s.type == type);
    if (index < 0 || index >= sections.length - 1) return;
    reorderSection(index, index + 1);
  }

  void setSectionVisible(StorefrontSectionType type, bool visible) {
    final section = state.draft.section(type);
    if (section == null) return;
    _applyDraft(state.draft.withSection(section.copyWith(visible: visible)));
  }

  void updateSectionSettings(
    StorefrontSectionType type,
    Map<String, dynamic> settings,
  ) {
    final section = state.draft.section(type);
    if (section == null) return;
    _applyDraft(
      state.draft.withSection(
          section.copyWith(settings: {...section.settings, ...settings})),
    );
  }

  void applyThemePreset(StorefrontThemePreset preset) {
    _applyDraft(
      state.draft.copyWith(theme: StorefrontDefaults.presetTheme(preset)),
    );
  }

  void updateTheme(StorefrontThemeConfig theme) {
    _applyDraft(state.draft.copyWith(theme: theme));
  }

  /// Patches the current draft theme (avoids stale closures from open pickers).
  void patchTheme(
    StorefrontThemeConfig Function(StorefrontThemeConfig current) patch,
  ) {
    _applyDraft(state.draft.copyWith(theme: patch(state.draft.theme)));
  }

  void updateStyle(StorefrontStyleConfig style) {
    _applyDraft(state.draft.copyWith(style: style));
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.addLast(state.draft);
    final previous = _undo.removeLast();
    final dirty = previous.encode() != (_savedDraft?.encode() ?? '');
    state = state.copyWith(
      draft: previous,
      hasUnsavedChanges: dirty,
      syncStatus: dirty
          ? StorefrontDraftSyncStatus.pending
          : StorefrontDraftSyncStatus.idle,
      previewPublished: false,
    );
    if (dirty) {
      _scheduleAutosave();
    } else {
      _autosaveTimer?.cancel();
    }
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.addLast(state.draft);
    final next = _redo.removeLast();
    final dirty = next.encode() != (_savedDraft?.encode() ?? '');
    state = state.copyWith(
      draft: next,
      hasUnsavedChanges: dirty,
      syncStatus: dirty
          ? StorefrontDraftSyncStatus.pending
          : StorefrontDraftSyncStatus.idle,
      previewPublished: false,
    );
    if (dirty) {
      _scheduleAutosave();
    } else {
      _autosaveTimer?.cancel();
    }
  }

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  Future<bool> saveDraft({bool fromAutosave = false}) async {
    if (state.publishing) return false;
    if (_inFlightSave != null) {
      final prior = await _inFlightSave;
      if (fromAutosave && !state.hasUnsavedChanges) return prior ?? true;
      if (state.saving || state.publishing) return prior ?? false;
    }
    if (!state.hasUnsavedChanges && fromAutosave) return true;

    _autosaveTimer?.cancel();
    final draftSnapshot = state.draft;
    final expectedUpdatedAt = state.updatedAt;
    state = state.copyWith(
      saving: true,
      syncStatus: StorefrontDraftSyncStatus.saving,
      clearError: true,
    );

    final future = () async {
      try {
        draftSnapshot.validate();
        final updatedAt = await _repository.saveDraft(
          config: draftSnapshot,
          expectedUpdatedAt: expectedUpdatedAt,
        );
        // Re-schedule if a newer local edit landed while saving.
        final stillMatches = state.draft.encode() == draftSnapshot.encode();
        _savedDraft = draftSnapshot;
        if (stillMatches) {
          state = state.copyWith(
            saving: false,
            updatedAt: updatedAt,
            hasUnsavedChanges: false,
            syncStatus: StorefrontDraftSyncStatus.saved,
          );
        } else {
          state = state.copyWith(
            saving: false,
            updatedAt: updatedAt,
            hasUnsavedChanges: true,
            syncStatus: StorefrontDraftSyncStatus.pending,
          );
          _scheduleAutosave();
        }
        return true;
      } catch (error) {
        final stale = error is StaleWriteException;
        state = state.copyWith(
          saving: false,
          syncStatus: StorefrontDraftSyncStatus.error,
          staleWrite: stale,
          errorMessage: mutationFailureMessageAr(
            error,
            fallback: 'تعذر حفظ مسودة تصميم المتجر.',
          ),
        );
        return false;
      }
    }();

    _inFlightSave = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlightSave, future)) {
        _inFlightSave = null;
      }
    }
  }

  Future<bool> publish() async {
    _autosaveTimer?.cancel();
    if (_inFlightSave != null) {
      await _inFlightSave;
    }
    state = state.copyWith(publishing: true, clearError: true);
    try {
      // Always send the current local draft so color-only publishes work even
      // when debounce has not flushed yet (atomic save+publish on the server).
      state.draft.validate();
      final publishedAt = await _repository.publish(
        config: state.draft,
        expectedUpdatedAt: state.updatedAt,
      );
      final adminState = await _repository.loadAdminState();
      _savedDraft = adminState.draftConfig;
      _undo.clear();
      _redo.clear();
      state = state.copyWith(
        publishing: false,
        draft: adminState.draftConfig,
        published: adminState.publishedConfig,
        updatedAt: adminState.updatedAt,
        publishedAt: publishedAt,
        hasUnsavedChanges: false,
        syncStatus: StorefrontDraftSyncStatus.idle,
        previewPublished: false,
      );
      return true;
    } catch (error) {
      final stale = error is StaleWriteException;
      state = state.copyWith(
        publishing: false,
        syncStatus: stale
            ? StorefrontDraftSyncStatus.error
            : state.syncStatus,
        staleWrite: stale,
        errorMessage: mutationFailureMessageAr(
          error,
          fallback: 'تعذر نشر تصميم المتجر.',
        ),
      );
      return false;
    }
  }

  Future<bool> resetDraft() async {
    _autosaveTimer?.cancel();
    state = state.copyWith(saving: true, clearError: true);
    try {
      final updatedAt = await _repository.resetDraft(
        expectedUpdatedAt: state.updatedAt,
      );
      final adminState = await _repository.loadAdminState();
      _savedDraft = adminState.draftConfig;
      _undo.clear();
      _redo.clear();
      state = state.copyWith(
        saving: false,
        draft: adminState.draftConfig,
        published: adminState.publishedConfig,
        updatedAt: updatedAt,
        hasUnsavedChanges: false,
        syncStatus: StorefrontDraftSyncStatus.saved,
        previewPublished: false,
      );
      return true;
    } catch (error) {
      final stale = error is StaleWriteException;
      state = state.copyWith(
        saving: false,
        syncStatus: StorefrontDraftSyncStatus.error,
        staleWrite: stale,
        errorMessage: mutationFailureMessageAr(
          error,
          fallback: 'تعذر استعادة التصميم الافتراضي.',
        ),
      );
      return false;
    }
  }
}
