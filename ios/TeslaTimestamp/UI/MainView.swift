#if canImport(UIKit)
import SwiftUI

public struct MainView: View {
    @ObservedObject var viewModel: MainViewModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var showFolderPicker = false
    @State private var showFilePicker = false
    @State private var showAlbumPicker = false
    @State private var showHelpAlert = false

    public init(viewModel: MainViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                heroHeader

                if viewModel.scanning {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(TeslaColors.brandRed)
                }

                ScrollView {
                    LazyVStack(spacing: 12) {
                        DataSourceCardView(
                            viewModel: viewModel,
                            onPickFolder: { showFolderPicker = true },
                            onPickFile: { showFilePicker = true },
                            onPickAlbum: { showAlbumPicker = true }
                        )

                        OverlayStyleCardView(viewModel: viewModel)

                        if viewModel.groups.isEmpty {
                            EmptyClipsCardView()
                        } else {
                            SelectionHeaderBarView(viewModel: viewModel)

                            ForEach(viewModel.groups) { group in
                                let groupSelectedIds = Set(
                                    group.files.filter { viewModel.selected.contains($0.id) }.map(\.id)
                                )
                                ClipCardView(
                                    group: group,
                                    selectedIds: groupSelectedIds,
                                    fullySelected: viewModel.isGroupFullySelected(group),
                                    partlySelected: viewModel.isGroupPartlySelected(group),
                                    isDisabled: viewModel.running,
                                    onToggleGroup: { checked in
                                        viewModel.setGroupSelected(group.id, isSelected: checked)
                                    },
                                    onToggleFile: { file, checked in
                                        viewModel.setFileSelected(file.id, isSelected: checked)
                                    },
                                    onPreviewClip: { file in
                                        viewModel.requestPreviewFor(fileId: file.id)
                                    }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                }

                bottomActionBar
            }
            .background(TeslaColors.background.ignoresSafeArea())

            if let toast = viewModel.toastMessage {
                Text(toast)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.black.opacity(0.82)))
                    .padding(.bottom, 104)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                viewModel.refreshUsbStatus()
            }
        }
        .sheet(isPresented: $showFolderPicker) {
            FolderDocumentPicker { url in
                viewModel.scanFolder(url: url)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showFilePicker) {
            VideoDocumentPicker { url in
                viewModel.scanDocument(url: url)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showAlbumPicker) {
            AlbumVideoPicker { providers in
                viewModel.scanAlbumProviders(providers)
            }
            .ignoresSafeArea()
        }
        .sheet(item: $viewModel.preview) { previewState in
            PreviewSheetView(
                preview: previewState,
                onGenerate: {
                    viewModel.preview = nil
                    viewModel.generate()
                },
                onClose: {
                    viewModel.preview = nil
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $viewModel.showResultsSheet) {
            ResultsSheetView(
                results: viewModel.results,
                failures: viewModel.failures,
                onPlay: { item in
                    viewModel.showResultsSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        viewModel.playResult(item)
                    }
                },
                onShare: { item in
                    viewModel.showResultsSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        viewModel.shareResult(item.url)
                    }
                },
                onClose: {
                    viewModel.showResultsSheet = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $viewModel.activePlayerItem) { playerItem in
            VideoPlayerSheetView(
                item: playerItem,
                onShare: {
                    let url = playerItem.url
                    viewModel.activePlayerItem = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        viewModel.shareResult(url)
                    }
                },
                onClose: {
                    viewModel.activePlayerItem = nil
                }
            )
            .presentationDetents([.height(410), .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $viewModel.activeShareItem) { shareItem in
            VideoShareSheet(fileURL: shareItem.url)
                .presentationDetents([.medium, .large])
        }
        .alert("使用说明", isPresented: $showHelpAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text("""
            1) 将特斯拉行车记录仪 U 盘通过 USB-C（或 Lightning 转 USB 转换器）连接到 iPhone / iPad。
            2) 点击“添加 U 盘 / 文件夹”，在系统文件选择器中进入 U 盘，选中 TeslaCam 文件夹并点右上角“打开”。
            3) 应用会自动按片段整理前视 / 后视 / 左后 / 右后 / 左右 B 柱视频，并读取 event.json 中的地点与事件原因。
            4) 勾选视频，可先点“预览”查看时间戳字号与位置。
            5) 点击“合成”，GPU 逐帧写入时间戳并硬件编码 H.264，成品自动保存到系统相册的 TeslaTimestamp 相簿中。

            提示：1 分钟原厂片段通常 4–10 秒即可完成。
            """)
        }
        .alert(
            "提示",
            isPresented: Binding(
                get: { viewModel.alertError != nil },
                set: { if !$0 { viewModel.alertError = nil } }
            )
        ) {
            Button("好", role: .cancel) {
                viewModel.alertError = nil
            }
        } message: {
            Text(viewModel.alertError ?? "")
        }
    }

    // MARK: - Brand Hero Header

    private var heroHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Tesla 时间戳")
                    .font(.system(size: 25, weight: .black))
                    .tracking(-0.4)
                    .foregroundStyle(.white)

                Text("行车记录仪 · 一键烧录时间戳 · 本地处理")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.84))
            }

            Spacer(minLength: 6)

            Button {
                Haptics.tap()
                if !viewModel.usbConnected {
                    viewModel.showToast("连接记录仪 U 盘后，点“添加 U 盘 / 文件夹”即可在“浏览”中选择该 U 盘")
                } else {
                    viewModel.refreshUsbStatus()
                }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.usbConnected ? Color(red: 0.30, green: 0.85, blue: 0.45) : Color.white.opacity(0.45))
                        .frame(width: 8, height: 8)

                    Text(viewModel.usbPillText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(1)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.16))
                )
            }
            .buttonStyle(.plain)

            Button {
                Haptics.tap()
                showHelpAlert = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("使用说明")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(
            LinearGradient(
                colors: [TeslaColors.brandRed, TeslaColors.brandRedDark, TeslaColors.heroEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: - Sticky Bottom Action Bar (Idle / Running / Done)

    private var bottomActionBar: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(TeslaColors.outline)

            Group {
                if viewModel.running {
                    runningBarContent
                } else if viewModel.doneVisible && !viewModel.results.isEmpty {
                    doneBarContent
                } else {
                    idleBarContent
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 14)
        }
        .background(
            TeslaColors.surface
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var idleBarContent: some View {
        let count = viewModel.selectedCount
        let canGenerate = count > 0 && !viewModel.scanning

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                if count == 0 {
                    Text("勾选片段后开始合成")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(TeslaColors.onSurface)
                    Text(viewModel.status)
                        .font(.system(size: 12))
                        .foregroundStyle(TeslaColors.onSurfaceVariant)
                        .lineLimit(1)
                } else {
                    let sizeText = TimeFormats.fileSize(viewModel.selectedSizeBytes)
                    Text("已选 \(count) 个视频 · 约 \(sizeText)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(TeslaColors.onSurface)
                        .lineLimit(1)
                    Text(viewModel.styleSummaryText)
                        .font(.system(size: 12))
                        .foregroundStyle(TeslaColors.onSurfaceVariant)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Button {
                Haptics.tap()
                viewModel.generate()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text(count > 0 ? "合成 \(count) 个视频" : "合成")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(height: 46)
                .background(
                    Capsule()
                        .fill(canGenerate ? TeslaColors.brandRed : TeslaColors.brandRed.opacity(0.38))
                )
            }
            .buttonStyle(.plain)
            .disabled(!canGenerate)
        }
    }

    private var runningBarContent: some View {
        let percent = min(100, max(0, Int((viewModel.progress * 100.0).rounded())))

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("正在合成 \(percent)%")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(TeslaColors.onSurface)

                    Text(viewModel.status)
                        .font(.system(size: 12))
                        .foregroundStyle(TeslaColors.onSurfaceVariant)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 4)

                Button {
                    Haptics.tap()
                    viewModel.cancelWork()
                } label: {
                    Text("取消")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(TeslaColors.brandRed)
                        .padding(.horizontal, 10)
                        .frame(height: 38)
                }
                .buttonStyle(.plain)
            }

            ProgressView(value: Double(min(1.0, max(0.0, viewModel.progress))), total: 1.0)
                .progressViewStyle(.linear)
                .tint(TeslaColors.brandRed)
        }
    }

    private var doneBarContent: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(TeslaColors.success)

            VStack(alignment: .leading, spacing: 2) {
                Text("已导出 \(viewModel.results.count) 个视频")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(TeslaColors.onSurface)
                    .lineLimit(1)

                Text("相册 · \(PhotoLibraryExporter.albumName)")
                    .font(.system(size: 12))
                    .foregroundStyle(TeslaColors.onSurfaceVariant)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button {
                Haptics.tap()
                viewModel.showResultsSheet = true
            } label: {
                Text("全部结果")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TeslaColors.brandRed)
                    .padding(.horizontal, 8)
                    .frame(height: 40)
            }
            .buttonStyle(.plain)

            Button {
                Haptics.tap()
                viewModel.playLatestResult()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("播放结果")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(Capsule().fill(TeslaColors.brandRed))
            }
            .buttonStyle(.plain)
        }
    }
}
#endif
