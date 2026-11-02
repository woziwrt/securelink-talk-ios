# Jak SecureLink Talk chrání hovory a zprávy

Co SecureLink Talk šifruje, co vidí server a kde jsou hranice ochrany. Stav k 2. 11. 2026 (iOS 1.1 build 31 – ke schválení, Android v2; **verze 1.0 v App Storu tyto změny ještě nemá**,
instalátor serveru v2; zákaznické servery se na v2 právě převádějí). Anglická verze:
[`SECURITY-DESIGN.md`](SECURITY-DESIGN.md).

SecureLink neprošel nezávislým auditem. Všechno je ale veřejné (GPL v3), takže si každé tvrzení může technik ověřit sám:
aplikace pro iOS (github.com/woziwrt/securelink-talk-ios), pro Android (github.com/woziwrt/securelink-android)
a instalátor serveru (github.com/woziwrt/securelink-server).

## 1. Uzavřený okruh na vlastním serveru zákazníka

- Každý zákazník (firma) má **vlastní server** (VPS pronajatý na jméno zákazníka). Jeden server = jeden **okruh**:
  účty vznikají jen tehdy, když je založí správce okruhu. Zvenku se nikdo zaregistrovat nemůže; žádný veřejný adresář,
  žádné hledání podle telefonního čísla, žádné propojení s jinými servery.
- Telefon se k účtu připojí **pozvánkou**: odkaz + šestimístný kód poslaný jinou cestou (telefonem, SMS, osobně), platí
  48 hodin, 5 pokusů; nová pozvánka zruší starší. Správce může předat i jednorázový QR kód (7 dní). Nastavení se stahuje
  jen přes HTTPS ze serveru, jehož certifikát podepsala naše certifikační autorita.
- Telefon může mít účty **víc okruhů** (třeba správce několika firem), ale jen když to **oba** okruhy povolí – správce to přepíná
  ve webu správy („Jiné okruhy v telefonu“). Okruh, který to nepovolí, zůstane v telefonu sám.
- Na čem stavíme: Linphone SDK 5.5.29 (Belledonne Communications), Flexisip 2.6 (SIP server, push, server pro skupinové
  zprávy), lime-server (klíče pro zprávy), před ním Kamailio 6.0.

## 2. Hovory

- Spojení se serverem: SIP přes **TLS 1.3**; certifikát serveru musí být podepsaný certifikační autoritou SecureLink,
  kterou má aplikace v sobě (jedna pro všechny okruhy; její klíč převádíme mimo server, offline).
- Domluva klíče: **ZRTP** přímo mezi oběma telefony, **hybridní X448 + ML-KEM-1024** (postkvantová). Server se domluvy
  klíče neúčastní. Ověřeno i na síti (ZRTP Commit `S512/AES3/GCM/X3M3/B32`).
- Hlas: SRTP s **AES-256-GCM**. Server hovor jen přeposílá v zašifrované podobě.
- Aplikace sama povolí **jen** ZRTP a **jen** postkvantové hybridní výměny klíče (X448 + ML-KEM-1024, X25519 + ML-KEM-512),
  ať server pošle cokoli – ani ovládnutý server nemůže hovor stáhnout na klasickou šifru.
- **Bezpečnostní slovo**: oba si ho na začátku hovoru přečtou a potvrdí. Kdyby se do hovoru vložil někdo třetí – i přes
  ovládnutý server – slova by se lišila. Potvrzení si aplikace u kontaktu pamatuje.

## 3. Zprávy

- Koncové šifrování **LIME** (X3DH + Double Ratchet od Belledonne, každá zpráva AES-256-GCM).
- Domluva klíče: **X448 + ML-KEM-1024** (postkvantová; lime-server větev `release/1.3`, kterou Belledonne zatím vede
  jako betu) spolu s X25519 + Kyber-512. Co používá váš okruh, ukáže aplikace v O aplikaci → Šifrování.
- Každé zařízení má vlastní klíč; nové zařízení kontaktu aplikace v konverzaci ohlásí („nové, zatím neověřené zařízení“).
- **Šifrování nejde vypnout.** Nešifrované zprávy odmítá přímo kód aplikace, ne jen nastavení serveru. Vyzkoušeno 2. 11. 2026:
  nešifrovaná zpráva podstrčená přímo do serveru (jako by ho někdo ovládl) – telefon ji odmítl a její text se nikde neukázal.
- Push (Apple / Google) nenese **žádný obsah ani jméno odesílatele**, jen probudí aplikaci. Oznámení v telefonu ukazuje
  jen „SecureLink – Zpráva přijata“ (bez odesílatele a textu; zmeškaný hovor bez jména volajícího). V datech oznámení zůstává
  adresa konverzace (aby klepnutí otevřelo správný rozhovor); nouzový PIN doručená oznámení smaže.
- Mizející zprávy jsou zapnuté v každé konverzaci (výchozí doba týden).

## 4. Co vidí server – a co ne

| správce serveru **vidí** | správce serveru **nevidí** |
|---|---|
| seznam účtů a jejich jména | obsah zpráv a příloh (koncově šifrované) |
| IP adresy připojených telefonů, časy přihlášení | co se v hovoru říká (klíč znají jen telefony) |
| kdo komu a kdy volá | databáze v telefonech |
| které účty spolu mají konverzaci | bezpečnostní slovo |
| velikost a čas šifrovaných zpráv | |

Co držíme co nejmenší:
- **Noční úklid** maže ze serveru konverzace smazaných účtů a zbytky záznamů. Živé konverzace zůstávají (jejich smazání
  by v současném Linphone SDK rozbilo doručování).
- Ostré verze aplikace zapisují do logu **jen chyby** (od iOS buildu 29 a Androidu v2). Starší verze zapisovaly podrobně,
  včetně staženého nastavení s heslem účtu – aktualizace staré logy jednou smaže. Logy zůstávají v telefonu.

## 5. V telefonu

- **Zámek:** aplikace se zamyká Face ID / otiskem / zámkem telefonu po 30 sekundách na pozadí a po 5 minutách bez dotyku.
- **PIN SecureLink (volitelný):** vlastní PIN místo zámku telefonu a k tomu **nouzový PIN**. Kdo zadá nouzový PIN, aplikace
  smaže všechny účty i s daty (konverzace, kontakty, historie hovorů, klíče pro zprávy), logy a nastavení, vypne PIN
  a ukáže prázdnou aplikaci. Funguje i tehdy, když je klávesnice po špatných pokusech zablokovaná. Nezakryje, že aplikace
  byla nainstalovaná a používaná. PINy se neukládají, jen jejich osolené otisky (PBKDF2-SHA256).
- **Data v telefonu:**
  - iOS: soubory chrání šifrování iOS (každý soubor vlastním klíčem); smazáním souboru se zahodí i jeho klíč, takže
    smazaná data z paměti telefonu obnovit nejdou.
  - Android: nové instalace mají databáze i nastavení šifrované **AES-256-GCM** s klíčem v Android Keystore; nouzový PIN
    ten klíč zničí. Instalace starší než 2. 11. 2026 mají databáze chráněné jen šifrováním Androidu, dokud se aplikace
    nepřeinstaluje.
- **Přihlašovací údaj účtu** (otisk hesla SIP, `ha1`) leží v nastavení aplikace v telefonu: na Androidu (nové instalace)
  šifrovaný klíčem v Android Keystore, na iOS chráněný šifrováním iOS a vyloučený ze záloh. Přesun do Klíčenky by nic
  nepřidal – forenzní nástroje ji v telefonu odemčeném od zapnutí vytáhnou stejně jako soubory. Co ho skutečně chrání:
  správce účet na serveru zablokuje a údaj okamžitě přestane platit; nouzový PIN ho smaže.
- Když je aplikace zamčená, její obsah není vidět ani pro čtení obrazovky (Android). Android zakazuje snímky a nahrávání
  obrazovky aplikace; iOS snímky obrazovky zakázat neumožňuje, ale při nahrávání, zrcadlení nebo sdílení obrazovky
  aplikace svůj obsah zakryje.
- Žádná analytika, žádné hlášení pádů, žádné reklamní identifikátory. Android používá Firebase jen pro push;
  aplikace pro iOS Firebase neobsahuje vůbec.

## 6. Správa a přístup podpory

- Správce okruhu spravuje účty ve webu správy na serveru zákazníka (HTTPS s klientským certifikátem + heslo, na každém
  serveru jiné).
- Podpora se na server dostane jen **SSH klíči vyrobenými pro tohoto zákazníka** (každý pod svým jménem, v záznamu přihlášení je vidět, kdo to byl).
  Univerzální klíč ke všem zákazníkům neexistuje. Zákazník může **přístup podpory kdykoli vypnout** ve webu správy.
- Zálohy serveru jsou šifrované (age) klíčem podpory a na přání i vlastním klíčem zákazníka.
- Správce může účet okamžitě zablokovat na serveru (heslo i klíče pro zprávy přestanou platit) a **vzdáleně ho
  vymazat**: telefon účet i s daty smaže, jakmile se připojí.

## 7. Před čím SecureLink nechrání

- Telefon, který už je napadený (škodlivý program s právy systému, odemčený telefon v cizích rukou).
- Údaje z kapitoly 4 pro toho, kdo ovládá server (zákazník, a podpora se souhlasem zákazníka).
- Skutečnost, že byl odeslán push – tu vidí Apple / Google (obsah ne).
- Cílené státní vyšetřování konkrétní osoby – to nemůže slíbit žádná aplikace sama o sobě.
- Postkvantová ochrana zpráv stojí na lime-serveru `release/1.3`, který Belledonne zatím nevydal jako stabilní.
