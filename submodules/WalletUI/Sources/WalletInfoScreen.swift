import Foundation
import UIKit
import AppBundle
import AccountContext
import TelegramPresentationData
import AsyncDisplayKit
import Display
import Postbox
import TelegramCore
import SolidRoundedButtonNode
import SwiftSignalKit
import MergeLists
import TelegramStringFormatting
import AnimationUI

public final class WalletInfoScreen: ViewController {
    private let context: AccountContext
    private let tonContext: TonContext
    private let walletInfo: WalletInfo
    private let address: String
    
    private var presentationData: PresentationData
    
    private let _ready = Promise<Bool>()
    override public var ready: Promise<Bool> {
        return self._ready
    }
    
    public init(context: AccountContext, tonContext: TonContext, walletInfo: WalletInfo, address: String) {
        self.context = context
        self.tonContext = tonContext
        self.walletInfo = walletInfo
        self.address = address
        
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        
        let defaultNavigationPresentationData = NavigationBarPresentationData(presentationTheme: self.presentationData.theme, presentationStrings: self.presentationData.strings)
        let navigationBarTheme = NavigationBarTheme(buttonColor: .white, disabledButtonColor: .white, primaryTextColor: .white, backgroundColor: .clear, separatorColor: .clear, badgeBackgroundColor: defaultNavigationPresentationData.theme.badgeBackgroundColor, badgeStrokeColor: defaultNavigationPresentationData.theme.badgeStrokeColor, badgeTextColor: defaultNavigationPresentationData.theme.badgeTextColor)
        
        super.init(navigationBarPresentationData: NavigationBarPresentationData(theme: navigationBarTheme, strings: defaultNavigationPresentationData.strings))
        
        self.statusBar.statusBarStyle = .White
        self.navigationPresentation = .modalInLargeLayout
        self.supportedOrientations = ViewControllerSupportedOrientations(regularSize: .all, compactSize: .portrait)
        self.navigationBar?.intrinsicCanTransitionInline = false
        
        self.navigationItem.backBarButtonItem = UIBarButtonItem(title: self.presentationData.strings.Common_Back, style: .plain, target: nil, action: nil)
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(image: generateTintedImage(image: UIImage(bundleImageName: "Wallet/NavigationSettingsIcon"), color: .white), style: .plain, target: self, action: #selector(self.settingsPressed))
        
        self.scrollToTop = { [weak self] in
            (self?.displayNode as? WalletInfoScreenNode)?.scrollToTop()
        }
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func backPressed() {
        self.dismiss()
    }
    
    @objc private func settingsPressed() {
        self.push(walletSettingsController(context: self.context, tonContext: self.tonContext, walletInfo: self.walletInfo))
    }
    
    override public func loadDisplayNode() {
        self.displayNode = WalletInfoScreenNode(account: self.context.account, tonContext: self.tonContext, presentationData: self.presentationData, walletInfo: self.walletInfo, address: self.address, sendAction: { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.push(walletSendScreen(context: strongSelf.context, tonContext: strongSelf.tonContext, randomId: arc4random64(), walletInfo: strongSelf.walletInfo))
        }, receiveAction: { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.push(walletReceiveScreen(context: strongSelf.context, address: strongSelf.address))
        }, openTransaction: { [weak self] transaction in
            guard let strongSelf = self else {
                return
            }
            strongSelf.push(walletTransactionInfoController(context: strongSelf.context, tonContext: strongSelf.tonContext, walletInfo: strongSelf.walletInfo, walletTransaction: transaction))
        }, present: { [weak self] c, a in
            guard let strongSelf = self else {
                return
            }
            strongSelf.present(c, in: .window(.root), with: a)
        })
        
        self.displayNodeDidLoad()
        
        self._ready.set((self.displayNode as! WalletInfoScreenNode).contentReady.get())
    }
    
    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        
        (self.displayNode as! WalletInfoScreenNode).containerLayoutUpdated(layout: layout, navigationHeight: self.navigationHeight, transition: transition)
    }
}

private final class WalletInfoBalanceNode: ASDisplayNode {
    let dateTimeFormat: PresentationDateTimeFormat
    
    let balanceIntegralTextNode: ImmediateTextNode
    let balanceFractionalTextNode: ImmediateTextNode
    let balanceIconNode: AnimatedStickerNode
    
    var balance: String = " " {
        didSet {
            let integralString = NSMutableAttributedString()
            let fractionalString = NSMutableAttributedString()
            if let range = self.balance.range(of: self.dateTimeFormat.decimalSeparator) {
                let integralPart = String(self.balance[..<range.lowerBound])
                let fractionalPart = String(self.balance[range.lowerBound...])
                integralString.append(NSAttributedString(string: integralPart, font: Font.medium(48.0), textColor: .white))
                fractionalString.append(NSAttributedString(string: fractionalPart, font: Font.medium(48.0), textColor: .white))
            } else {
                integralString.append(NSAttributedString(string: self.balance, font: Font.medium(48.0), textColor: .white))
            }
            self.balanceIntegralTextNode.attributedText = integralString
            self.balanceFractionalTextNode.attributedText = fractionalString
        }
    }
    
    var isLoading: Bool = true
    
    init(account: Account, theme: PresentationTheme, dateTimeFormat: PresentationDateTimeFormat) {
        self.dateTimeFormat = dateTimeFormat
        
        self.balanceIntegralTextNode = ImmediateTextNode()
        self.balanceIntegralTextNode.displaysAsynchronously = false
        self.balanceIntegralTextNode.attributedText = NSAttributedString(string: " ", font: Font.bold(39.0), textColor: .white)
        self.balanceIntegralTextNode.layer.minificationFilter = .linear
        
        self.balanceFractionalTextNode = ImmediateTextNode()
        self.balanceFractionalTextNode.displaysAsynchronously = false
        self.balanceFractionalTextNode.attributedText = NSAttributedString(string: " ", font: Font.bold(39.0), textColor: .white)
        self.balanceFractionalTextNode.layer.minificationFilter = .linear
        
        self.balanceIconNode = AnimatedStickerNode()
        if let path = getAppBundle().path(forResource: "WalletIntroStatic", ofType: "tgs") {
            self.balanceIconNode.setup(account: account, resource: .localFile(path), width: 120, height: 120, mode: .direct)
            self.balanceIconNode.visibility = true
        }
        
        super.init()
        
        self.addSubnode(self.balanceIntegralTextNode)
        self.addSubnode(self.balanceFractionalTextNode)
        self.addSubnode(self.balanceIconNode)
    }
    
    func update(width: CGFloat, scaleTransition: CGFloat, transition: ContainedViewLayoutTransition) -> CGFloat {
        let sideInset: CGFloat = 16.0
        let balanceIconSpacing: CGFloat = scaleTransition * 0.0 + (1.0 - scaleTransition) * (-12.0)
        let balanceVerticalIconOffset: CGFloat = scaleTransition * (-6.0) + (1.0 - scaleTransition) * (-2.0)
        
        let balanceIntegralTextSize = self.balanceIntegralTextNode.updateLayout(CGSize(width: width - sideInset * 2.0, height: 200.0))
        let balanceFractionalTextSize = self.balanceFractionalTextNode.updateLayout(CGSize(width: width - sideInset * 2.0, height: 200.0))
        let balanceIconSize = CGSize(width: 60.0, height: 60.0)
        
        let integralScale: CGFloat = scaleTransition * 1.0 + (1.0 - scaleTransition) * 0.8
        let fractionalScale: CGFloat = scaleTransition * 0.5 + (1.0 - scaleTransition) * 0.8
        
        let balanceOrigin = CGPoint(x: floor((width - balanceIntegralTextSize.width * integralScale - balanceFractionalTextSize.width * fractionalScale - balanceIconSpacing - balanceIconSize.width / 2.0) / 2.0), y: 0.0)
        
        let balanceIntegralTextFrame = CGRect(origin: balanceOrigin, size: balanceIntegralTextSize)
        let apparentBalanceIntegralTextFrame = CGRect(origin: balanceIntegralTextFrame.origin, size: CGSize(width: balanceIntegralTextFrame.width * integralScale, height: balanceIntegralTextFrame.height * integralScale))
        var balanceFractionalTextFrame = CGRect(origin: CGPoint(x: balanceIntegralTextFrame.maxX, y: balanceIntegralTextFrame.maxY - balanceFractionalTextSize.height), size: balanceFractionalTextSize)
        let apparentBalanceFractionalTextFrame = CGRect(origin: balanceFractionalTextFrame.origin, size: CGSize(width: balanceFractionalTextFrame.width * fractionalScale, height: balanceFractionalTextFrame.height * fractionalScale))
        
        balanceFractionalTextFrame.origin.x -= (balanceFractionalTextFrame.width / 4.0) * scaleTransition + 0.25 * (balanceFractionalTextFrame.width / 2.0) * (1.0 - scaleTransition)
        balanceFractionalTextFrame.origin.y += balanceFractionalTextFrame.height * 0.5 * (0.8 - fractionalScale)
        
        let balanceIconFrame: CGRect
        balanceIconFrame = CGRect(origin: CGPoint(x: apparentBalanceFractionalTextFrame.maxX + balanceIconSpacing * integralScale, y: balanceIntegralTextFrame.midY - balanceIconSize.height / 2.0 + balanceVerticalIconOffset), size: balanceIconSize)
        
        transition.updateFrameAsPositionAndBounds(node: self.balanceIntegralTextNode, frame: balanceIntegralTextFrame)
        transition.updateTransformScale(node: self.balanceIntegralTextNode, scale: integralScale)
        transition.updateFrameAsPositionAndBounds(node: self.balanceFractionalTextNode, frame: balanceFractionalTextFrame)
        transition.updateTransformScale(node: self.balanceFractionalTextNode, scale: fractionalScale)
        
        self.balanceIconNode.updateLayout(size: balanceIconFrame.size)
        transition.updateFrameAsPositionAndBounds(node: self.balanceIconNode, frame: balanceIconFrame)
        transition.updateTransformScale(node: self.balanceIconNode, scale: scaleTransition * 1.0 + (1.0 - scaleTransition) * 0.8)
        
        return balanceIntegralTextSize.height
    }
}

private final class WalletInfoHeaderNode: ASDisplayNode {
    var balance: Int64?
    var isRefreshing: Bool = false
    var timestamp: Int32?
    
    let balanceNode: WalletInfoBalanceNode
    private let refreshNode: WalletRefreshNode
    private let balanceSubtitleNode: ImmediateTextNode
    private let receiveButtonNode: SolidRoundedButtonNode
    private let sendButtonNode: SolidRoundedButtonNode
    private let headerBackgroundNode: ASDisplayNode
    private let headerCornerNode: ASImageNode
    
    init(account: Account, presentationData: PresentationData, sendAction: @escaping () -> Void, receiveAction: @escaping () -> Void) {
        self.balanceNode = WalletInfoBalanceNode(account: account, theme: presentationData.theme, dateTimeFormat: presentationData.dateTimeFormat)
        
        self.balanceSubtitleNode = ImmediateTextNode()
        self.balanceSubtitleNode.displaysAsynchronously = false
        self.balanceSubtitleNode.attributedText = NSAttributedString(string: presentationData.strings.Wallet_Info_YourBalance, font: Font.regular(13), textColor: UIColor(white: 1.0, alpha: 0.6))
        
        self.headerBackgroundNode = ASDisplayNode()
        self.headerBackgroundNode.backgroundColor = .black
        
        self.headerCornerNode = ASImageNode()
        self.headerCornerNode.displaysAsynchronously = false
        self.headerCornerNode.displayWithoutProcessing = true
        self.headerCornerNode.image = generateImage(CGSize(width: 20.0, height: 10.0), rotatedContext: { size, context in
            context.setFillColor(UIColor.black.cgColor)
            context.fill(CGRect(origin: CGPoint(), size: size))
            context.setBlendMode(.copy)
            context.setFillColor(UIColor.clear.cgColor)
            context.fillEllipse(in: CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: CGSize(width: 20.0, height: 20.0)))
        })?.stretchableImage(withLeftCapWidth: 10, topCapHeight: 1)
        
        self.receiveButtonNode = SolidRoundedButtonNode(title: presentationData.strings.Wallet_Info_Receive, icon: UIImage(bundleImageName: "Wallet/ReceiveButtonIcon"), theme: SolidRoundedButtonTheme(backgroundColor: .white, foregroundColor: .black), height: 50.0, cornerRadius: 10.0, gloss: false)
        self.sendButtonNode = SolidRoundedButtonNode(title: presentationData.strings.Wallet_Info_Send, icon: UIImage(bundleImageName: "Wallet/SendButtonIcon"), theme: SolidRoundedButtonTheme(backgroundColor: .white, foregroundColor: .black), height: 50.0, cornerRadius: 10.0, gloss: false)
        
        self.refreshNode = WalletRefreshNode(strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat)
        
        super.init()
        
        self.addSubnode(self.headerBackgroundNode)
        self.addSubnode(self.headerCornerNode)
        self.addSubnode(self.receiveButtonNode)
        self.addSubnode(self.sendButtonNode)
        self.addSubnode(self.balanceNode)
        self.addSubnode(self.balanceSubtitleNode)
        self.addSubnode(self.refreshNode)
        
        self.receiveButtonNode.pressed = {
            receiveAction()
        }
        self.sendButtonNode.pressed = {
            sendAction()
        }
    }
    
    func update(size: CGSize, navigationHeight: CGFloat, offset: CGFloat, transition: ContainedViewLayoutTransition) {
        let sideInset: CGFloat = 16.0
        let buttonSideInset: CGFloat = 48.0
        let titleSpacing: CGFloat = 10.0
        let termsSpacing: CGFloat = 10.0
        let buttonHeight: CGFloat = 50.0
        let balanceSubtitleSpacing: CGFloat = 0.0
        
        let minOffset = navigationHeight
        let maxOffset = size.height
        
        let minHeaderOffset = minOffset
        let maxHeaderOffset = (minOffset + maxOffset) / 2.0
        
        let effectiveOffset = max(offset, navigationHeight)
        
        let minButtonsOffset = maxOffset - buttonHeight - sideInset
        let maxButtonsOffset = maxOffset
        let buttonTransition: CGFloat = max(0.0, min(1.0, (effectiveOffset - minButtonsOffset) / (maxButtonsOffset - minButtonsOffset)))
        let buttonAlpha = buttonTransition * 1.0
        
        let balanceSubtitleSize = self.balanceSubtitleNode.updateLayout(CGSize(width: size.width - sideInset * 2.0, height: 200.0))
        
        let headerScaleTransition: CGFloat = max(0.0, min(1.0, (effectiveOffset - minHeaderOffset) / (maxHeaderOffset - minHeaderOffset)))
        
        let balanceHeight = self.balanceNode.update(width: size.width, scaleTransition: headerScaleTransition, transition: transition)
        let balanceSize = CGSize(width: size.width, height: balanceHeight)
        
        let maxHeaderScale: CGFloat = min(1.0, (size.width - 40.0) / balanceSize.width)
        let minHeaderScale: CGFloat = min(0.435, (size.width - 80.0 * 2.0) / balanceSize.width)
        
        let minHeaderHeight: CGFloat = balanceSize.height + balanceSubtitleSize.height + balanceSubtitleSpacing
        
        let minHeaderY = navigationHeight - 44.0 + floor((44.0 - minHeaderHeight) / 2.0)
        let maxHeaderY = floor((size.height - balanceSize.height) / 2.0 - balanceSubtitleSize.height)
        let headerPositionTransition: CGFloat = max(0.0, (effectiveOffset - minHeaderOffset) / (maxOffset - minHeaderOffset))
        let headerY = headerPositionTransition * maxHeaderY + (1.0 - headerPositionTransition) * minHeaderY
        let headerScale = headerScaleTransition * maxHeaderScale + (1.0 - headerScaleTransition) * minHeaderScale
        
        let refreshSize = CGSize(width: 0.0, height: 0.0)
        transition.updateFrame(node: self.refreshNode, frame: CGRect(origin: CGPoint(x: floor((size.width - refreshSize.width) / 2.0), y: navigationHeight - 44.0 + floor((44.0 - refreshSize.height) / 2.0)), size: refreshSize))
        transition.updateAlpha(node: self.refreshNode, alpha: headerScaleTransition)
        if self.balance == nil {
            self.refreshNode.update(state: .pullToRefresh(self.timestamp ?? 0, 0.0))
        } else if self.isRefreshing {
            self.refreshNode.update(state: .refreshing)
        } else {
            let refreshOffset: CGFloat = 20.0
            let refreshScaleTransition: CGFloat = max(0.0, (offset - maxOffset) / refreshOffset)
            self.refreshNode.update(state: .pullToRefresh(self.timestamp ?? 0, refreshScaleTransition * 0.1))
        }
        
        let balanceFrame = CGRect(origin: CGPoint(x: 0.0, y: headerY), size: balanceSize)
        transition.updateFrame(node: self.balanceNode, frame: balanceFrame)
        transition.updateSublayerTransformScale(node: self.balanceNode, scale: headerScale)
        
        let balanceSubtitleOffset = headerScaleTransition * 27.0 + (1.0 - headerScaleTransition) * 9.0
        let balanceSubtitleFrame = CGRect(origin: CGPoint(x: floor((size.width - balanceSubtitleSize.width) / 2.0), y: balanceFrame.midY + balanceSubtitleOffset), size: balanceSubtitleSize)
        transition.updateFrameAdditive(node: self.balanceSubtitleNode, frame: balanceSubtitleFrame)
        
        let headerHeight: CGFloat = 1000.0
        transition.updateFrame(node: self.headerBackgroundNode, frame: CGRect(origin: CGPoint(x: -1.0, y: effectiveOffset - headerHeight), size: CGSize(width: size.width + 2.0, height: headerHeight)))
        transition.updateFrame(node: self.headerCornerNode, frame: CGRect(origin: CGPoint(x: 0.0, y: effectiveOffset), size: CGSize(width: size.width, height: 10.0)))
        
        let buttonOffset = effectiveOffset
        
        let leftButtonFrame = CGRect(origin: CGPoint(x: sideInset, y: buttonOffset - sideInset - buttonHeight), size: CGSize(width: floor((size.width - sideInset * 3.0) / 2.0), height: buttonHeight))
        let sendButtonFrame = CGRect(origin: CGPoint(x: leftButtonFrame.maxX + sideInset, y: leftButtonFrame.minY), size: CGSize(width: size.width - leftButtonFrame.maxX - sideInset * 2.0, height: buttonHeight))
        let fullButtonFrame = CGRect(origin: CGPoint(x: sideInset, y: buttonOffset - sideInset - buttonHeight), size: CGSize(width: size.width - sideInset * 2.0, height: buttonHeight))
        
        var receiveButtonFrame: CGRect
        if let balance = self.balance, balance > 0 {
            receiveButtonFrame = leftButtonFrame
            self.receiveButtonNode.isHidden = false
            self.sendButtonNode.isHidden = false
        } else {
            receiveButtonFrame = fullButtonFrame
            if self.balance == nil {
                self.receiveButtonNode.isHidden = true
                self.sendButtonNode.isHidden = true
            } else {
                self.receiveButtonNode.isHidden = false
                self.sendButtonNode.isHidden = true
            }
        }
        if self.balance == nil {
            self.balanceNode.isHidden = true
            self.balanceSubtitleNode.isHidden = true
            self.refreshNode.isHidden = true
        } else {
            self.balanceNode.isHidden = false
            self.balanceSubtitleNode.isHidden = false
            self.refreshNode.isHidden = false
        }
        transition.updateFrame(node: self.receiveButtonNode, frame: receiveButtonFrame)
        transition.updateAlpha(node: self.receiveButtonNode, alpha: buttonAlpha)
        self.receiveButtonNode.updateLayout(width: receiveButtonFrame.width, transition: transition)
        transition.updateFrame(node: self.sendButtonNode, frame: sendButtonFrame)
        transition.updateAlpha(node: self.sendButtonNode, alpha: buttonAlpha)
        self.sendButtonNode.updateLayout(width: sendButtonFrame.width, transition: transition)
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let result = self.sendButtonNode.hitTest(self.view.convert(point, to: self.sendButtonNode.view), with: event) {
            return result
        }
        if let result = self.receiveButtonNode.hitTest(self.view.convert(point, to: self.receiveButtonNode.view), with: event) {
            return result
        }
        return nil
    }
    
    func becameReady(animated: Bool) {
        if animated {
            self.sendButtonNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
            self.receiveButtonNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
            self.balanceNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
            self.balanceSubtitleNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
            self.refreshNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
        }
        self.balanceNode.isLoading = false
    }
}

private struct WalletInfoListTransaction {
    let deletions: [ListViewDeleteItem]
    let insertions: [ListViewInsertItem]
    let updates: [ListViewUpdateItem]
}

private enum WalletInfoListEntryId: Hashable {
    case empty
    case transaction(WalletTransactionId)
}

private enum WalletInfoListEntry: Equatable, Comparable, Identifiable {
    case empty(String)
    case transaction(Int, WalletTransaction)
    
    var stableId: WalletInfoListEntryId {
        switch self {
        case .empty:
            return .empty
        case let .transaction(_, transaction):
            return .transaction(transaction.transactionId)
        }
    }
    
    static func <(lhs: WalletInfoListEntry, rhs: WalletInfoListEntry) -> Bool {
        switch lhs {
        case .empty:
            switch rhs {
            case .empty:
                return false
            case .transaction:
                return true
            }
        case let .transaction(lhsIndex, _):
            switch rhs {
            case .empty:
                return false
            case let .transaction(rhsIndex, _):
                return lhsIndex < rhsIndex
            }
        }
    }
    
    func item(account: Account, theme: PresentationTheme, strings: PresentationStrings, dateTimeFormat: PresentationDateTimeFormat, action: @escaping (WalletTransaction) -> Void, displayAddressContextMenu: @escaping (ASDisplayNode, CGRect) -> Void) -> ListViewItem {
        switch self {
        case let .empty(address):
            return WalletInfoEmptyItem(account: account, theme: theme, strings: strings, address: address, displayAddressContextMenu: { node, frame in
                displayAddressContextMenu(node, frame)
            })
        case let .transaction(_, transaction):
            return WalletInfoTransactionItem(theme: theme, strings: strings, dateTimeFormat: dateTimeFormat, walletTransaction: transaction, action: {
                action(transaction)
            })
        }
    }
}

private func preparedTransition(from fromEntries: [WalletInfoListEntry], to toEntries: [WalletInfoListEntry], account: Account, presentationData: PresentationData, action: @escaping (WalletTransaction) -> Void, displayAddressContextMenu: @escaping (ASDisplayNode, CGRect) -> Void) -> WalletInfoListTransaction {
    let (deleteIndices, indicesAndItems, updateIndices) = mergeListsStableWithUpdates(leftList: fromEntries, rightList: toEntries)
    
    let deletions = deleteIndices.map { ListViewDeleteItem(index: $0, directionHint: nil) }
    let insertions = indicesAndItems.map { ListViewInsertItem(index: $0.0, previousIndex: $0.2, item: $0.1.item(account: account, theme: presentationData.theme, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat, action: action, displayAddressContextMenu: displayAddressContextMenu), directionHint: nil) }
    let updates = updateIndices.map { ListViewUpdateItem(index: $0.0, previousIndex: $0.2, item: $0.1.item(account: account, theme: presentationData.theme, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat, action: action, displayAddressContextMenu: displayAddressContextMenu), directionHint: nil) }
    
    return WalletInfoListTransaction(deletions: deletions, insertions: insertions, updates: updates)
}

private final class WalletInfoScreenNode: ViewControllerTracingNode {
    private let account: Account
    private let tonContext: TonContext
    private var presentationData: PresentationData
    private let walletInfo: WalletInfo
    private let address: String
    
    private let openTransaction: (WalletTransaction) -> Void
    private let present: (ViewController, Any?) -> Void
    
    private let hapticFeedback = HapticFeedback()
    
    private let headerNode: WalletInfoHeaderNode
    private let listNode: ListView
    private let loadingIndicator: UIActivityIndicatorView
    
    private var enqueuedTransactions: [WalletInfoListTransaction] = []
    
    private var validLayout: (ContainerViewLayout, CGFloat)?
    
    private let stateDisposable = MetaDisposable()
    private let transactionListDisposable = MetaDisposable()
    
    private var listOffset: CGFloat?
    private var reloadingState: Bool = false
    private var loadingMoreTransactions: Bool = false
    private var canLoadMoreTransactions: Bool = true
    
    fileprivate var combinedState: CombinedWalletState?
    private var currentEntries: [WalletInfoListEntry]?
    
    private var isReady: Bool = false
    
    let contentReady = Promise<Bool>()
    private var didSetContentReady = false
    
    private var updateTimestampTimer: SwiftSignalKit.Timer?
    
    init(account: Account, tonContext: TonContext, presentationData: PresentationData, walletInfo: WalletInfo, address: String, sendAction: @escaping () -> Void, receiveAction: @escaping () -> Void, openTransaction: @escaping (WalletTransaction) -> Void, present: @escaping (ViewController, Any?) -> Void) {
        self.account = account
        self.tonContext = tonContext
        self.presentationData = presentationData
        self.walletInfo = walletInfo
        self.address = address
        self.openTransaction = openTransaction
        self.present = present
        
        self.headerNode = WalletInfoHeaderNode(account: account, presentationData: presentationData, sendAction: sendAction, receiveAction: receiveAction)
        
        self.listNode = ListView()
        self.listNode.verticalScrollIndicatorColor = UIColor(white: 0.0, alpha: 0.3)
        self.listNode.verticalScrollIndicatorFollowsOverscroll = true
        self.listNode.isHidden = true
        
        self.loadingIndicator = UIActivityIndicatorView(style: .whiteLarge)
        
        super.init()
        
        self.backgroundColor = self.presentationData.theme.list.itemBlocksBackgroundColor
        
        self.addSubnode(self.listNode)
        self.addSubnode(self.headerNode)
        self.view.addSubview(self.loadingIndicator)
        
        var canBeginRefresh = true
        var isScrolling = false
        self.listNode.beganInteractiveDragging = {
            isScrolling = true
        }
        self.listNode.endedInteractiveDragging = {
            isScrolling = false
        }
        
        self.listNode.updateFloatingHeaderOffset = { [weak self] offset, listTransition in
            guard let strongSelf = self, let (layout, navigationHeight) = strongSelf.validLayout else {
                return
            }
            
            let headerHeight: CGFloat = navigationHeight + 260.0
            strongSelf.listOffset = offset
            
            if strongSelf.isReady {
                if !strongSelf.reloadingState && canBeginRefresh && isScrolling {
                    if offset >= headerHeight + 100.0 {
                        canBeginRefresh = false
                        strongSelf.hapticFeedback.impact()
                        strongSelf.refreshTransactions()
                    }
                }
                strongSelf.headerNode.update(size: strongSelf.headerNode.bounds.size, navigationHeight: navigationHeight, offset: offset, transition: listTransition)
            }
        }
        
        self.listNode.visibleBottomContentOffsetChanged = { [weak self] offset in
            guard let strongSelf = self else {
                return
            }
            guard case let .known(value) = offset, value < 100.0 else {
                return
            }
            if !strongSelf.loadingMoreTransactions && !strongSelf.reloadingState && strongSelf.canLoadMoreTransactions {
                strongSelf.loadMoreTransactions()
            }
        }
        
        self.listNode.didEndScrolling = { [weak self] in
            canBeginRefresh = true
            
            guard let strongSelf = self, let (_, navigationHeight) = strongSelf.validLayout else {
                return
            }
            switch strongSelf.listNode.visibleContentOffset() {
            case let .known(offset):
                if offset < strongSelf.listNode.insets.top {
                    /*if offset > strongSelf.listNode.insets.top / 2.0 {
                        strongSelf.scrollToHideHeader()
                    } else {
                        strongSelf.scrollToTop()
                    }*/
                }
            default:
                break
            }
        }
        
        self.refreshTransactions()
        
        self.updateTimestampTimer = SwiftSignalKit.Timer(timeout: 1.0, repeat: true, completion: { [weak self] in
            guard let strongSelf = self, let combinedState = strongSelf.combinedState, !strongSelf.reloadingState else {
                return
            }
            strongSelf.headerNode.timestamp = Int32(clamping: combinedState.timestamp)
        }, queue: .mainQueue())
        self.updateTimestampTimer?.start()
    }
    
    deinit {
        self.stateDisposable.dispose()
        self.transactionListDisposable.dispose()
        self.updateTimestampTimer?.invalidate()
    }
    
    func scrollToHideHeader() {
        guard let (_, navigationHeight) = self.validLayout else {
            return
        }
        self.listNode.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: [.Synchronous, .LowLatency], scrollToItem: ListViewScrollToItem(index: 0, position: .top(navigationHeight), animated: true, curve: .Spring(duration: 0.4), directionHint: .Up), updateSizeAndInsets: nil, stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
    }
    
    func scrollToTop() {
        self.listNode.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: [.Synchronous, .LowLatency], scrollToItem: ListViewScrollToItem(index: 0, position: .top(0.0), animated: true, curve: .Spring(duration: 0.4), directionHint: .Up), updateSizeAndInsets: nil, stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
    }
    
    func containerLayoutUpdated(layout: ContainerViewLayout, navigationHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        let isFirstLayout = self.validLayout == nil
        self.validLayout = (layout, navigationHeight)
        
        let indicatorSize = self.loadingIndicator.bounds.size
        self.loadingIndicator.frame = CGRect(origin: CGPoint(x: floor((layout.size.width - indicatorSize.width) / 2.0), y: floor((layout.size.height - indicatorSize.height) / 2.0)), size: indicatorSize)
        
        let headerHeight: CGFloat = navigationHeight + 260.0
        let topInset: CGFloat = headerHeight
        
        let visualHeaderHeight: CGFloat
        let visualHeaderOffset: CGFloat
        if !self.isReady {
            visualHeaderHeight = layout.size.height
            visualHeaderOffset = visualHeaderHeight
        } else {
            visualHeaderHeight = headerHeight
            visualHeaderOffset = self.listOffset ?? 0.0
        }
        let visualListOffset = visualHeaderHeight - headerHeight
        
        let headerFrame = CGRect(origin: CGPoint(), size: CGSize(width: layout.size.width, height: visualHeaderHeight))
        transition.updateFrame(node: self.headerNode, frame: headerFrame)
        self.headerNode.update(size: headerFrame.size, navigationHeight: navigationHeight, offset: visualHeaderOffset, transition: transition)
        
        transition.updateFrame(node: self.listNode, frame: CGRect(origin: CGPoint(x: 0.0, y: visualListOffset), size: layout.size))
        
        var duration: Double = 0.0
        var curve: UInt = 0
        switch transition {
        case .immediate:
            break
        case let .animated(animationDuration, animationCurve):
            duration = animationDuration
            switch animationCurve {
            case .easeInOut, .custom:
                break
            case .spring:
                curve = 7
            }
        }
        
        let listViewCurve: ListViewAnimationCurve
        if curve == 7 {
            listViewCurve = .Spring(duration: duration)
        } else {
            listViewCurve = .Default(duration: duration)
        }
        
        self.listNode.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: [.Synchronous, .LowLatency], scrollToItem: nil, updateSizeAndInsets: ListViewUpdateSizeAndInsets(size: layout.size, insets: UIEdgeInsets(top: topInset, left: 0.0, bottom: layout.intrinsicInsets.bottom, right: 0.0), headerInsets: UIEdgeInsets(top: navigationHeight, left: 0.0, bottom: layout.intrinsicInsets.bottom, right: 0.0), scrollIndicatorInsets: UIEdgeInsets(top: topInset + 3.0, left: 0.0, bottom: layout.intrinsicInsets.bottom, right: 0.0), duration: duration, curve: listViewCurve), stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
        
        if isFirstLayout {
            while !self.enqueuedTransactions.isEmpty {
                self.dequeueTransaction()
            }
        }
    }
    
    private func refreshTransactions() {
        self.transactionListDisposable.set(nil)
        self.loadingMoreTransactions = true
        self.reloadingState = true
        
        self.headerNode.isRefreshing = true
        
        self.stateDisposable.set((getCombinedWalletState(postbox: self.account.postbox, walletInfo: self.walletInfo, tonInstance: self.tonContext.instance)
        |> deliverOnMainQueue).start(next: { [weak self] value in
            guard let strongSelf = self else {
                return
            }
            let combinedState: CombinedWalletState?
            switch value {
            case let .cached(state):
                if strongSelf.combinedState != nil {
                    return
                }
                if state == nil {
                    strongSelf.loadingIndicator.startAnimating()
                } else {
                    strongSelf.loadingIndicator.stopAnimating()
                    strongSelf.loadingIndicator.isHidden = true
                }
                combinedState = state
            case let .updated(state):
                strongSelf.loadingIndicator.stopAnimating()
                strongSelf.loadingIndicator.isHidden = true
                combinedState = state
            }
            
            strongSelf.combinedState = combinedState
            if let combinedState = combinedState {
                strongSelf.headerNode.balanceNode.balance = formatBalanceText(max(0, combinedState.walletState.balance), decimalSeparator: strongSelf.presentationData.dateTimeFormat.decimalSeparator)
                strongSelf.headerNode.balance = max(0, combinedState.walletState.balance)
                
                if strongSelf.isReady, let (layout, navigationHeight) = strongSelf.validLayout {
                    strongSelf.containerLayoutUpdated(layout: layout, navigationHeight: navigationHeight, transition: .immediate)
                }
                
                strongSelf.reloadingState = false
                
                strongSelf.headerNode.timestamp = Int32(clamping: combinedState.timestamp)
                
                if strongSelf.isReady, let (layout, navigationHeight) = strongSelf.validLayout {
                    strongSelf.headerNode.update(size: strongSelf.headerNode.bounds.size, navigationHeight: navigationHeight, offset: strongSelf.listOffset ?? 0.0, transition: .immediate)
                }
                
                strongSelf.transactionsLoaded(isReload: true, transactions: combinedState.topTransactions)
                
                strongSelf.headerNode.isRefreshing = false
                
                if strongSelf.isReady, let (layout, navigationHeight) = strongSelf.validLayout {
                    strongSelf.headerNode.update(size: strongSelf.headerNode.bounds.size, navigationHeight: navigationHeight, offset: strongSelf.listOffset ?? 0.0, transition: .animated(duration: 0.2, curve: .easeInOut))
                }
                
                let wasReady = strongSelf.isReady
                strongSelf.isReady = strongSelf.combinedState != nil
                
                if strongSelf.isReady && !wasReady {
                    if let (layout, navigationHeight) = strongSelf.validLayout {
                        strongSelf.headerNode.update(size: strongSelf.headerNode.bounds.size, navigationHeight: navigationHeight, offset: layout.size.height, transition: .immediate)
                    }
                    
                    strongSelf.becameReady(animated: strongSelf.didSetContentReady)
                }
            }
            
            if !strongSelf.didSetContentReady {
                strongSelf.didSetContentReady = true
                strongSelf.contentReady.set(.single(true))
            }
        }, error: { [weak self] _ in
            guard let strongSelf = self else {
                return
            }
            
                strongSelf.reloadingState = false
            
            if let combinedState = strongSelf.combinedState {
                strongSelf.headerNode.timestamp = Int32(clamping: combinedState.timestamp)
            }
                
            if strongSelf.isReady, let (layout, navigationHeight) = strongSelf.validLayout {
                strongSelf.headerNode.update(size: strongSelf.headerNode.bounds.size, navigationHeight: navigationHeight, offset: strongSelf.listOffset ?? 0.0, transition: .immediate)
            }
                
            strongSelf.loadingMoreTransactions = false
            strongSelf.canLoadMoreTransactions = false
                
            strongSelf.headerNode.isRefreshing = false
                
            if strongSelf.isReady, let (layout, navigationHeight) = strongSelf.validLayout {
                strongSelf.headerNode.update(size: strongSelf.headerNode.bounds.size, navigationHeight: navigationHeight, offset: strongSelf.listOffset ?? 0.0, transition: .animated(duration: 0.2, curve: .easeInOut))
            }
            
            if !strongSelf.didSetContentReady {
                strongSelf.didSetContentReady = true
                strongSelf.contentReady.set(.single(true))
            }
            
            strongSelf.present(standardTextAlertController(theme: AlertControllerTheme(presentationTheme: strongSelf.presentationData.theme), title: strongSelf.presentationData.strings.Wallet_Info_RefreshErrorTitle, text: strongSelf.presentationData.strings.Wallet_Info_RefreshErrorText, actions: [
                TextAlertAction(type: .defaultAction, title: strongSelf.presentationData.strings.Common_OK, action: {
                })
            ], actionLayout: .vertical), nil)
        }))
    }
    
    private func loadMoreTransactions() {
        if self.loadingMoreTransactions {
            return
        }
        self.loadingMoreTransactions = true
        var lastTransactionId: WalletTransactionId?
        if let last = self.currentEntries?.last {
            switch last {
            case let .transaction(_, transaction):
                lastTransactionId = transaction.transactionId
            case .empty:
                break
            }
        }
        self.transactionListDisposable.set((getWalletTransactions(address: self.address, previousId: lastTransactionId, tonInstance: self.tonContext.instance)
        |> deliverOnMainQueue).start(next: { [weak self] transactions in
            guard let strongSelf = self else {
                return
            }
            strongSelf.transactionsLoaded(isReload: false, transactions: transactions)
        }, error: { [weak self] _ in
            guard let strongSelf = self else {
                return
            }
        }))
    }
    
    private func transactionsLoaded(isReload: Bool, transactions: [WalletTransaction]) {
        self.loadingMoreTransactions = false
        self.canLoadMoreTransactions = transactions.count > 2
        
        var updatedEntries: [WalletInfoListEntry] = []
        if isReload {
            var existingIds = Set<WalletTransactionId>()
            for transaction in transactions {
                if !existingIds.contains(transaction.transactionId) {
                    existingIds.insert(transaction.transactionId)
                    updatedEntries.append(.transaction(updatedEntries.count, transaction))
                }
            }
            if updatedEntries.isEmpty {
                updatedEntries.append(.empty(self.address))
            }
        } else {
            updatedEntries = self.currentEntries ?? []
            updatedEntries = updatedEntries.filter { entry in
                if case .empty = entry {
                    return false
                } else {
                    return true
                }
            }
            var existingIds = Set<WalletTransactionId>()
            for entry in updatedEntries {
                switch entry {
                case let .transaction(_, transaction):
                    existingIds.insert(transaction.transactionId)
                case .empty:
                    break
                }
            }
            for transaction in transactions {
                if !existingIds.contains(transaction.transactionId) {
                    existingIds.insert(transaction.transactionId)
                    updatedEntries.append(.transaction(updatedEntries.count, transaction))
                }
            }
            if updatedEntries.isEmpty {
                updatedEntries.append(.empty(self.address))
            }
        }
        
        let transaction = preparedTransition(from: self.currentEntries ?? [], to: updatedEntries, account: self.account, presentationData: self.presentationData, action: { [weak self] transaction in
            guard let strongSelf = self else {
                return
            }
            strongSelf.openTransaction(transaction)
        }, displayAddressContextMenu: { [weak self] node, frame in
            guard let strongSelf = self else {
                return
            }
            let address = strongSelf.address
            let contextMenuController = ContextMenuController(actions: [ContextMenuAction(content: .text(title: strongSelf.presentationData.strings.Conversation_ContextMenuCopy, accessibilityLabel: strongSelf.presentationData.strings.Conversation_ContextMenuCopy), action: {
                UIPasteboard.general.string = address
            })])
            strongSelf.present(contextMenuController, ContextMenuControllerPresentationArguments(sourceNodeAndRect: { [weak self] in
                if let strongSelf = self {
                    return (node, frame.insetBy(dx: 0.0, dy: -2.0), strongSelf, strongSelf.view.bounds)
                } else {
                    return nil
                }
            }))
        })
        self.currentEntries = updatedEntries
        
        self.enqueuedTransactions.append(transaction)
        self.dequeueTransaction()
    }
    
    private func dequeueTransaction() {
        guard let layout = self.validLayout, let transaction = self.enqueuedTransactions.first else {
            return
        }
        
        self.enqueuedTransactions.remove(at: 0)
        
        var options = ListViewDeleteAndInsertOptions()
        options.insert(.Synchronous)
        options.insert(.PreferSynchronousResourceLoading)
        options.insert(.PreferSynchronousDrawing)
        
        self.listNode.transaction(deleteIndices: transaction.deletions, insertIndicesAndItems: transaction.insertions, updateIndicesAndItems: transaction.updates, options: options, updateSizeAndInsets: nil, updateOpaqueState: nil, completion: { _ in
        })
    }
    
    private func becameReady(animated: Bool) {
        self.listNode.isHidden = false
        self.loadingIndicator.stopAnimating()
        self.loadingIndicator.isHidden = true
        self.headerNode.becameReady(animated: animated)
        if let (layout, navigationHeight) = self.validLayout {
            self.containerLayoutUpdated(layout: layout, navigationHeight: navigationHeight, transition: animated ? .animated(duration: 0.5, curve: .spring) : .immediate)
        }
    }
}