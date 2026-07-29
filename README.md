# Špacírkovník — iOS

Natívna iOS verzia hry **Špacírkovník** (location-based prechádzková hra po Petržalke
a okolí). Je to SwiftUI port [Android appky](../spacirkovnik) — zdieľa **rovnaký Firebase
backend** aj **rovnaké JSON definície hier**, takže obsah netreba duplikovať.

## Stack

| Vrstva | Android (origin) | iOS (tu) |
|--------|------------------|----------|
| UI | Jetpack Compose | SwiftUI |
| Architektúra | MVVM (`ViewModel` + `State`) | MVVM (`@Observable`) |
| Backend | Firebase Auth + Realtime DB | Firebase Auth + Realtime DB (rovnaký projekt) |
| Dáta hier | JSON cez Retrofit | JSON cez `URLSession` (Codable) |
| Mapy / GPS | Mapbox + Play Services Location | MapKit + Core Location |
| Nákupy | Google Play Billing | StoreKit 2 |

## Štruktúra

```
Spacirkovnik/
├── App/            SpacirkovnikApp (@main), RootView
├── Models/         GameInfo, GameDefinition, GameScreen, GameAnswer, GameConsent, Gender
├── Data/           ApiService (Firebase REST), GameCacheManager (offline cache), ConsentStore
├── ViewModels/     GameListViewModel, GameDataViewModel, LocationManager, AuthViewModel, PurchaseManager
├── Views/          GameListView, GamePlayView, NavigationTargetView, AuthSheet, GameConsentSheet
├── Theme/          Color+Hex, AppColor (paleta ako android Color.kt)
└── Resources/      Assets.xcassets
```

Projekt **nemá commitnutý `.xcodeproj`** — generuje sa z `project.yml` cez
[XcodeGen](https://github.com/yonaskolb/XcodeGen), takže nevznikajú merge konflikty.

## Build na macOS

> Na Linuxe sa iOS appka **nedá** zostaviť ani spustiť — nasledujúce kroky rob na Macu s Xcode.

1. **Nainštaluj XcodeGen** (raz):
   ```bash
   brew install xcodegen
   ```

2. **Vygeneruj Xcode projekt** (z koreňa repa):
   ```bash
   xcodegen generate
   open Spacirkovnik.xcodeproj
   ```

3. **Pridaj Firebase config:** v [Firebase konzole](https://console.firebase.google.com)
   pridaj do projektu `spacirkovnik-app` novú iOS aplikáciu s bundle ID `sk.spacirkovnik`,
   stiahni `GoogleService-Info.plist` a vlož ho do priečinka `Spacirkovnik/Resources/`
   (potom ho znova spusti `xcodegen generate`). Súbor je v `.gitignore`.

4. **Nastav Signing:** v Xcode → target *Spacirkovnik* → *Signing & Capabilities* vyber
   svoj Apple Developer tím (alebo doplň `DEVELOPMENT_TEAM` v `project.yml`).

5. **Spusti** na simulátore alebo zariadení (⌘R). Bez prihlásenia/nákupov funguje katalóg
   aj voľná hra `lesnicka-palica`.

## Čo ešte treba doplniť (TODO na Macu)

- [ ] `GoogleService-Info.plist` + overiť `FirebaseApp.configure()`.
- [ ] **Google Sign-In** (balík `GoogleSignIn`) a linkovanie email ↔ Google účtu — viď `AuthViewModel`.
- [ ] **App Store Connect**: vytvoriť Non-Consumable produkty s ID podľa `googlePlayProductId`
      z katalógu (napr. `tajomstvo_janka_krala`) — viď `PurchaseManager`.
- [ ] Po nákupe zapísať aktiváciu do Firebase (`activations/{uid}/{gameId} = true`),
      aby sa hra odomkla aj na Androide.
- [ ] App ikona (`Assets.xcassets/AppIcon`).
- [ ] **Marketingový súhlas** (`marketingConsent/{uid}` vo Firebase) a jeho prepínač v účte —
      na Androide pribudol v júni 2026, tu zatiaľ nie je.
- [ ] Uložený postup v špacírke (android `GameProgressManager`) — „Pokračovať" / „Odznova".
```
