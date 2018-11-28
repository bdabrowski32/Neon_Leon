//    The MIT License (MIT)
//
//    Copyright (c) 2015-2017 Dominik Ringler
//
//    Permission is hereby granted, free of charge, to any person obtaining a copy
//    of this software and associated documentation files (the "Software"), to deal
//    in the Software without restriction, including without limitation the rights
//    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//    copies of the Software, and to permit persons to whom the Software is
//    furnished to do so, subject to the following conditions:
//
//    The above copyright notice and this permission notice shall be included in all
//    copies or substantial portions of the Software.
//
//    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//    SOFTWARE.

import GoogleMobileAds

/// LocalizedString (todo)
private extension String {
    static let sorry = "Sorry"
    static let ok = "OK"
    static let noVideo = "No video available to watch at the moment."
}

/// SwiftyAdDelegate
protocol SwiftyAdDelegate: class {
    /// SwiftyAd did open
    func swiftyAdDidOpen(_ swiftyAd: SwiftyAd)
    /// SwiftyAd did close
    func swiftyAdDidClose(_ swiftyAd: SwiftyAd)
    /// SwiftyAd did reward user
    func swiftyAd(_ swiftyAd: SwiftyAd, didRewardUserWithAmount rewardAmount: Int)
}

/**
 AdMob
 
 A singleton class to manage adverts from Google AdMob.
 */
final class SwiftyAd: NSObject {
    
    // MARK: - Static Properties
    
    /// Shared instance
    static let shared = SwiftyAd()
    
    // MARK: - Properties
    
    /// Banner position
    enum BannerPosition {
        case bottom
        case top
    }
    
    /// Delegates
    weak var delegate: SwiftyAdDelegate?
    
    /// Check if interstitial video is ready (e.g to show alternative ad)
    /// Will try to reload an ad if it returns false.
    var isInterstitialReady: Bool {
        guard let ad = interstitialAd, ad.isReady else {
            print("AdMob interstitial ad is not ready, reloading...")
            loadInterstitialAd()
            return false
        }
        return true
    }
    
    /// Check if reward video is ready (e.g to hide a reward video button)
    /// Will try to reload an ad if it returns false.
    var isRewardedVideoReady: Bool {
        guard let ad = rewardedVideoAd, ad.isReady else {
            print("AdMob reward video is not ready, reloading...")
            loadRewardedVideoAd()
            return false
        }
        return true
    }
    
    /// Remove ads
    var isRemoved = false {
        didSet {
            guard isRemoved else { return }
            removeBanner()
            interstitialAd?.delegate = nil
            interstitialAd = nil
        }
    }
    
    /// Ads
    var bannerViewConstraint: NSLayoutConstraint?
    var bannerAdView: GADBannerView?
    var interstitialAd: GADInterstitial?
    var rewardedVideoAd: GADRewardBasedVideoAd?
    
    /// Ad Unit IDs. Gets set to real ID in setup method
    var bannerViewAdUnitID = "ca-app-pub-1397382354626971/3371077102"
    //Production:"ca-app-pub-1397382354626971/3371077102"
    //Test: "ca-app-pub-1397382354626971/2613363359"
    var interstitialAdUnitID = "ca-app-pub-1397382354626971/2613363359"
    //Production: "ca-app-pub-1397382354626971/2613363359"
    //Test: "ca-app-pub-3940256099942544/4411468910"
    var rewardedVideoAdUnitID = ""
    
    /// Interval counter
    private var intervalCounter = 0
    
    /// Reward amount backup
    var rewardAmountBackup = 1
    
    /// Banner position
    var bannerPosition = BannerPosition.bottom
    
    /// Banner size
    var bannerSize: GADAdSize {
        let isLandscape = UIApplication.shared.statusBarOrientation.isLandscape
        return isLandscape ? kGADAdSizeSmartBannerLandscape : kGADAdSizeSmartBannerPortrait
    }
    
    /// Banner animation duration
    let bannerAnimationDuration = 1.8
    
    // MARK: - Init
    
    private override init() {
        super.init()
        print("AdMob SDK version \(GADRequest.sdkVersion())")
    }
    
    func test(vc: UIViewController) {
        animateBannerToOffScreenPosition(self.bannerAdView!, from: vc)
    }
    
    // MARK: - Setup
    
    /// Set up admob helper
    ///
    /// - parameter bannerID: The banner adUnitID for this app.
    /// - parameter interstitialID: The interstitial adUnitID for this app.
    /// - parameter rewardedVideoID: The rewarded video adUnitID for this app.
    /// - parameter rewardAmountBackup: The rewarded amount backup used incase the server amount cannot be fetched or is 0. Defaults to 1.
    func setup(withBannerID bannerID: String, interstitialID: String, rewardedVideoID: String, rewardAmountBackup: Int = 1) {
        self.rewardAmountBackup = rewardAmountBackup
        
        #if !DEBUG
        bannerViewAdUnitID = bannerID
        interstitialAdUnitID = interstitialID
        rewardedVideoAdUnitID = rewardedVideoID
        #endif
        
        // Preload inter and reward ads first time
        loadInterstitialAd()
        loadRewardedVideoAd()
    }
    
    // MARK: - Show Banner
    
    /// Show banner ad
    ///
    /// - parameter viewController: The view controller that will present the ad.
    /// - parameter position: The position of the banner. Defaults to bottom.
    func showBanner(from viewController: UIViewController, at position: BannerPosition = .bottom) {
        guard !isRemoved else { return }
        bannerPosition = position
        loadBannerAd(from: viewController)
    }
    
    // MARK: - Show Interstitial
    
    /// Show interstitial ad randomly
    ///
    /// - parameter viewController: The view controller that will present the ad.
    /// - parameter interval: The interval of when to show the ad, e.g every 4th time the method is called. Defaults to nil.
    func showInterstitial(from viewController: UIViewController, withInterval interval: Int? = nil) {
        guard !isRemoved, isInterstitialReady else { return }
        
        if let interval = interval {
            intervalCounter += 1
            guard intervalCounter >= interval else { return }
            intervalCounter = 0
        }
        
        interstitialAd?.present(fromRootViewController: viewController)
    }
    
    // MARK: - Show Reward Video
    
    /// Show rewarded video ad
    ///
    /// - parameter viewController: The view controller that will present the ad.
    func showRewardedVideo(from viewController: UIViewController) {
        guard isRewardedVideoReady else {
            showNoVideoAvailableAlert(from: viewController)
            return
        }
        
        rewardedVideoAd?.present(fromRootViewController: viewController)
    }
    
    // MARK: - Remove Banner
    
    /// Remove banner ads
    func removeBanner() {
        bannerAdView?.delegate = nil
        bannerAdView?.removeFromSuperview()
        bannerAdView = nil
        bannerViewConstraint = nil
    }
    
    // MARK: - Update For Orientation
    
    /// Orientation changed
    func updateOrientation() {
        bannerAdView?.adSize = bannerSize
    }
}

// MARK: - Load Ad

private extension SwiftyAd {
    
    func loadBannerAd(from viewController: UIViewController) {
        removeBanner()
        bannerAdView = GADBannerView(adSize: bannerSize)
        
        guard let bannerAdView = bannerAdView else { return }
        
        // Create ad
        bannerAdView.adUnitID = bannerViewAdUnitID
        bannerAdView.delegate = self
        bannerAdView.rootViewController = viewController
        bannerAdView.isHidden = true
        bannerAdView.translatesAutoresizingMaskIntoConstraints = false
        viewController.view.addSubview(bannerAdView)
        
        // Add constraints
        let layoutGuide: UILayoutGuide
        if #available(iOS 11, *) {
            layoutGuide = viewController.view.safeAreaLayoutGuide
        } else {
            layoutGuide = viewController.view.layoutMarginsGuide
        }
        
        bannerAdView.leftAnchor.constraint(equalTo: layoutGuide.leftAnchor).isActive = true
        bannerAdView.rightAnchor.constraint(equalTo: layoutGuide.rightAnchor).isActive = true
        
        switch bannerPosition {
        case .bottom:
            bannerViewConstraint = bannerAdView.bottomAnchor.constraint(equalTo: layoutGuide.bottomAnchor)
        case .top:
            bannerViewConstraint = bannerAdView.topAnchor.constraint(equalTo: layoutGuide.topAnchor)
        }
        
        animateBannerToOffScreenPosition(bannerAdView, from: viewController, withAnimation: false)
        bannerViewConstraint?.isActive = true
        
        // Request ad
        let request = GADRequest()
        #if DEBUG
        request.testDevices = [kGADSimulatorID]
        #endif
        bannerAdView.load(request)
    }
    
    func loadInterstitialAd() {
        interstitialAd = GADInterstitial(adUnitID: interstitialAdUnitID)
        
        guard let interstitialAd = interstitialAd else { return }
        
        interstitialAd.delegate = self
        
        let request = GADRequest()
        #if DEBUG
        request.testDevices = [kGADSimulatorID]
        #endif
        interstitialAd.load(request)
    }
    
    func loadRewardedVideoAd() {
        rewardedVideoAd = GADRewardBasedVideoAd.sharedInstance()
        
        guard let rewardedVideoAd = rewardedVideoAd else { return }
        
        rewardedVideoAd.delegate = self
        
        let request = GADRequest()
        #if DEBUG
        request.testDevices = [kGADSimulatorID]
        #endif
        rewardedVideoAd.load(request, withAdUnitID: rewardedVideoAdUnitID)
    }
}

// MARK: - GAD Banner View Delegate

extension SwiftyAd: GADBannerViewDelegate {
    
    func adViewDidReceiveAd(_ bannerView: GADBannerView) {
        print("AdMob banner did receive ad from: \(bannerView.adNetworkClassName ?? "")")
        bannerView.isHidden = false
        animateBannerToOnScreenPosition(bannerView, from: bannerView.rootViewController)
    }
    
    func adViewWillPresentScreen(_ bannerView: GADBannerView) {
        delegate?.swiftyAdDidOpen(self)
    }
    
    func adViewWillLeaveApplication(_ bannerView: GADBannerView) {
        delegate?.swiftyAdDidOpen(self)
    }
    
    func adViewWillDismissScreen(_ bannerView: GADBannerView) {
        
    }
    
    func adViewDidDismissScreen(_ bannerView: GADBannerView) {
        delegate?.swiftyAdDidClose(self)
    }
    
    func adView(_ bannerView: GADBannerView, didFailToReceiveAdWithError error: GADRequestError) {
        print(error.localizedDescription)
        animateBannerToOffScreenPosition(bannerView, from: bannerView.rootViewController)
    }
}

// MARK: - GAD Interstitial Delegate

extension SwiftyAd: GADInterstitialDelegate {
    
    func interstitialDidReceiveAd(_ ad: GADInterstitial) {
        print("AdMob interstitial did receive ad from: \(ad.adNetworkClassName ?? "")")
    }
    
    func interstitialWillPresentScreen(_ ad: GADInterstitial) {
        delegate?.swiftyAdDidOpen(self)
    }
    
    func interstitialWillLeaveApplication(_ ad: GADInterstitial) {
        delegate?.swiftyAdDidOpen(self)
    }
    
    func interstitialWillDismissScreen(_ ad: GADInterstitial) {
    }
    
    func interstitialDidDismissScreen(_ ad: GADInterstitial) {
        delegate?.swiftyAdDidClose(self)
        loadInterstitialAd()
    }
    
    func interstitialDidFail(toPresentScreen ad: GADInterstitial) {
    }
    
    func interstitial(_ ad: GADInterstitial, didFailToReceiveAdWithError error: GADRequestError) {
        print(error.localizedDescription)
        // Do not reload here as it might cause endless preloads when internet problems
    }
}

// MARK: - GAD Reward Based Video Ad Delegate

extension SwiftyAd: GADRewardBasedVideoAdDelegate {
    
    func rewardBasedVideoAdDidReceive(_ rewardBasedVideoAd: GADRewardBasedVideoAd) {
        print("AdMob reward based video did receive ad from: \(rewardBasedVideoAd.adNetworkClassName ?? "")")
    }
    
    func rewardBasedVideoAdDidStartPlaying(_ rewardBasedVideoAd: GADRewardBasedVideoAd) {
        delegate?.swiftyAdDidOpen(self)
    }
    
    func rewardBasedVideoAdDidOpen(_ rewardBasedVideoAd: GADRewardBasedVideoAd) {
    }
    
    func rewardBasedVideoAdWillLeaveApplication(_ rewardBasedVideoAd: GADRewardBasedVideoAd) {
        delegate?.swiftyAdDidOpen(self)
    }
    
    func rewardBasedVideoAdDidClose(_ rewardBasedVideoAd: GADRewardBasedVideoAd) {
        delegate?.swiftyAdDidClose(self)
        loadRewardedVideoAd()
    }
    
    func rewardBasedVideoAd(_ rewardBasedVideoAd: GADRewardBasedVideoAd, didFailToLoadWithError error: Error) {
        print(error.localizedDescription)
        // Do not reload here as it might cause endless preloads when internet problems
    }
    
    func rewardBasedVideoAd(_ rewardBasedVideoAd: GADRewardBasedVideoAd, didRewardUserWith reward: GADAdReward) {
        print("AdMob reward based video ad did reward user with \(reward)")
        
        let rewardInt = Int(truncating: reward.amount)
        let rewardAmount = rewardInt <= 0 ? rewardAmountBackup : rewardInt
        delegate?.swiftyAd(self, didRewardUserWithAmount: rewardAmount)
    }
}

// MARK: - Banner Position

private extension SwiftyAd {
    
    func animateBannerToOnScreenPosition(_ bannerAd: GADBannerView, from viewController: UIViewController?) {
        bannerAd.isHidden = false
        bannerViewConstraint?.constant = 0
        
        UIView.animate(withDuration: bannerAnimationDuration) {
            viewController?.view.layoutIfNeeded()
        }
    }
    
    func animateBannerToOffScreenPosition(_ bannerAd: GADBannerView, from viewController: UIViewController?, withAnimation: Bool = true) {
        switch bannerPosition {
        case .bottom:
            bannerViewConstraint?.constant = 0 + (bannerAd.frame.height * 3)
        case .top:
            bannerViewConstraint?.constant = 0 - (bannerAd.frame.height * 3)
        }
        
        guard withAnimation else { return }
        
        UIView.animate(withDuration: bannerAnimationDuration, animations: {
            viewController?.view.layoutIfNeeded()
        }, completion: { isSuccess in
            bannerAd.isHidden = true
        })
    }
}

// MARK: - Alert

private extension SwiftyAd {
    
    func showNoVideoAvailableAlert(from viewController: UIViewController) {
        let alertController = UIAlertController(title: .sorry, message: .noVideo, preferredStyle: .alert)
        let okAction = UIAlertAction(title: .ok, style: .cancel)
        alertController.addAction(okAction)
        
        DispatchQueue.main.async {
            viewController.present(alertController, animated: true)
        }
    }
}

// MARK: - Print

private extension SwiftyAd {
    
    /// Overrides the default print method so it print statements only show when in DEBUG mode
    func print(_ items: Any...) {
        #if DEBUG
        Swift.print(items)
        #endif
    }
}
