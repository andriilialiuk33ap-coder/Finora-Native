import SwiftUI
import PhotosUI
import Speech
import AVFoundation
import UserNotifications

// Presentation options are independent of the stored financial records.
private struct FinamiMaskKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues { var finamiMask: Bool { get { self[FinamiMaskKey.self] } set { self[FinamiMaskKey.self]=newValue } } }
enum FinamiDesign: String, CaseIterable, Identifiable {
    case signature = "Signature", pure = "Pure", aurora = "Aurora", canvas = "Canvas", obsidian = "Obsidian", pulse = "Pulse", nord = "Nord", rose = "Rose", graphite = "Graphite", ocean = "Ocean"
    case darkClassic = "Dark Classic", graphiteGlass = "Graphite Glass", premiumNeon = "Premium Neon", cleanLight = "Clean Light"
    case blackTitanium = "Black Titanium", digitalBank = "Digital Bank", compactPro = "Compact Pro", liquidGlass = "Liquid Glass", emeraldAnalytics = "Emerald Analytics", whiteStudio = "White Studio"
    case midnightBlue = "Midnight Blue", amethyst = "Amethyst", warmSand = "Warm Sand", carbonRed = "Carbon Red", nordicWhite = "Nordic White"
    static let simplicity: [Self] = [.midnightBlue,.amethyst,.warmSand,.carbonRed,.nordicWhite]
    static let revolution: [Self] = [.blackTitanium,.digitalBank,.compactPro,.liquidGlass,.emeraldAnalytics,.whiteStudio]
    static let featured: [Self] = [.darkClassic,.graphiteGlass,.premiumNeon,.cleanLight]
    var id: String { rawValue }
    var tint: Color {
        switch self {
        case .signature: return Color(red:0.20,green:0.69,blue:0.50)
        case .pure,.pulse: return .blue
        case .aurora: return .indigo
        case .canvas: return Color(red:0.64,green:0.32,blue:0.20)
        case .obsidian,.darkClassic: return Color(red:0.82,green:0.66,blue:0.34)
        case .nord:return .teal
        case .rose:return .pink
        case .graphite:return .gray
        case .ocean:return .cyan
        case .graphiteGlass:return Color(red:0.49,green:0.69,blue:0.88)
        case .premiumNeon:return Color(red:0.30,green:0.82,blue:0.69)
        case .cleanLight:return Color(red:0.12,green:0.36,blue:0.70)
        case .blackTitanium,.compactPro:return Color(red:0.82,green:0.68,blue:0.44)
        case .digitalBank,.liquidGlass:return Color(red:0.49,green:0.69,blue:0.90)
        case .emeraldAnalytics:return Color(red:0.36,green:0.76,blue:0.57)
        case .whiteStudio:return Color(red:0.18,green:0.18,blue:0.20)
        case .midnightBlue:return Color(red:0.53,green:0.69,blue:0.99)
        case .amethyst:return Color(red:0.76,green:0.64,blue:0.96)
        case .warmSand:return Color(red:0.48,green:0.31,blue:0.16)
        case .carbonRed:return Color(red:0.96,green:0.46,blue:0.48)
        case .nordicWhite:return Color(red:0.18,green:0.34,blue:0.60)
        }
    }
    var corner: CGFloat {
        switch self { case .pure,.cleanLight,.whiteStudio: return 16; case .canvas,.rose: return 24; case .pulse,.nord,.graphite,.compactPro: return 14; case .obsidian,.darkClassic,.blackTitanium: return 18; case .graphiteGlass,.liquidGlass: return 22; case .premiumNeon,.midnightBlue: return 20; case .warmSand,.amethyst: return 24; case .carbonRed,.nordicWhite: return 14; default: return 20 }
    }
    var font: Font.Design { self == .canvas || self == .rose || self == .warmSand ? .rounded : .default }
    var scheme: ColorScheme? { switch self { case .signature,.aurora,.obsidian,.graphite,.ocean,.darkClassic,.graphiteGlass,.premiumNeon,.blackTitanium,.digitalBank,.compactPro,.liquidGlass,.emeraldAnalytics,.midnightBlue,.amethyst,.carbonRed:return .dark; default:return .light } }
    var description: String {
        switch self {
        case .midnightBlue:return "Нічний синій · кобальтовий акцент"
        case .amethyst:return "Фіолетові поверхні · м’які лінії"
        case .warmSand:return "Теплий пісочний · природні відтінки"
        case .carbonRed:return "Карбон · червоні акценти"
        case .nordicWhite:return "Холодний білий · синя типографіка"
        case .blackTitanium:return "Матовий чорний · рівна сітка · золото"
        case .digitalBank:return "Банківські картки · розширені показники"
        case .compactPro:return "Щільний список · мінімум ефектів"
        case .liquidGlass:return "М’які контури · опційне скло"
        case .emeraldAnalytics:return "Аналітика · смарагдові акценти"
        case .whiteStudio:return "Світлий · монохромні поверхні"
        case .darkClassic:return "Чорний · матове золото · стримані платежі"
        case .graphiteGlass:return "Графіт · скло за бажанням · прохолодний акцент"
        case .premiumNeon:return "Темний · тонкі м’ятні контури · фінансові статуси"
        case .cleanLight:return "Світлий · чисті поверхні · контрастна типографіка"
        case .signature:return "Смарагдовий · м’які картки"
        case .pure:return "Світлий · чиста типографіка"
        case .aurora:return "Скло · багатошарові фони"
        case .canvas:return "Теплі ілюстрації · округлі форми"
        case .obsidian:return "Темний · золоті акценти"
        case .pulse:return "Банківський · виразні акценти"
        case .nord:return "Скандинавський · лаконічні плитки"
        case .rose:return "Пастель · м’які акценти"
        case .graphite:return "Монохром · компактна типографіка"
        case .ocean:return "Океан · глибокі градієнти"
        }
    }
    var monochrome: Bool { self == .darkClassic || self == .obsidian || self == .graphite || self == .blackTitanium || self == .compactPro || self == .whiteStudio }
}
enum FinamiCardTemplate: String, CaseIterable, Identifiable {
    case automatic = "За дизайном", gradient = "Gradient", minimal = "Minimal", glass = "Glass", soft = "Soft", bank = "Bank", neon = "Neon", stripe = "Stripe", compact = "Compact", illustrated = "Illustrated", premium = "Premium"
    var id:String { rawValue }
}
struct FinamiCardStyle: ViewModifier {
    @EnvironmentObject var s: Store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var tint: Color
    var template: String? = nil
    func body(content: Content) -> some View {
        let design = FinamiDesign(rawValue:s.db.preferences?.design ?? "Dark Classic") ?? .darkClassic
        let style = FinamiCardTemplate(rawValue:template ?? s.db.preferences?.cardTemplate ?? "За дизайном") ?? .automatic
        let radius: CGFloat = s.db.preferences?.designRadius.map { CGFloat(FinamiDesignPolicy.radius($0)) } ?? (style == .minimal ? 8 : style == .compact ? 12 : design.corner)
        let economical = s.db.preferences?.designLowEffects == true
        let accent = finamiDesignAccent(s.db.preferences?.designAccent) ?? (design.monochrome && style == .automatic ? design.tint : tint)
        let base = finamiDesignSurface(design, scheme: scheme)
        let glass = style == .glass || (style == .automatic && [.aurora,.graphiteGlass,.liquidGlass].contains(design))
        let gradient = [.gradient,.premium,.bank,.illustrated].contains(style) || (style == .automatic && [.signature,.pulse,.ocean,.graphiteGlass,.digitalBank,.emeraldAnalytics,.midnightBlue,.amethyst].contains(design))
        let neon = style == .neon || (style == .automatic && design == .premiumNeon)
        content.background {
            ZStack(alignment:.leading) {
                RoundedRectangle(cornerRadius:radius).fill(base)
                if glass && !reduceTransparency && !economical && (style == .glass || design == .liquidGlass) { RoundedRectangle(cornerRadius:radius).fill(.regularMaterial) }
                if economical && style != .automatic && (gradient || glass) { RoundedRectangle(cornerRadius:radius).fill(accent.opacity(style == .premium ? 0.19 : style == .glass ? 0.06 : 0.13)) }
                if !economical && (gradient || glass) { RoundedRectangle(cornerRadius:radius).fill(LinearGradient(colors:[accent.opacity(style == .premium ? 0.29 : style == .bank ? 0.21 : style == .gradient ? 0.25 : 0.13),accent.opacity(0.015)],startPoint:.topLeading,endPoint:.bottomTrailing)) }
                if style == .illustrated { Circle().strokeBorder(accent.opacity(0.22),lineWidth:16).frame(width:100,height:100).frame(maxWidth:.infinity,alignment:.trailing).offset(x:25,y:-24).accessibilityHidden(true) }
                if style == .bank { Capsule().fill(accent.opacity(0.6)).frame(width:28,height:3).frame(maxHeight:.infinity,alignment:.top).padding(10) }
                if style == .soft || (style == .automatic && [.canvas,.rose,.nord,.warmSand,.nordicWhite].contains(design)) { RoundedRectangle(cornerRadius:radius).fill(accent.opacity(0.07)) }
                if style == .stripe { Capsule().fill(accent).frame(width:3).padding(.vertical,10) }
            }
        }.clipShape(RoundedRectangle(cornerRadius:radius))
         .overlay { RoundedRectangle(cornerRadius:radius).strokeBorder(neon ? accent.opacity(0.72) : style == .premium ? accent.opacity(0.42) : style == .compact ? accent.opacity(0.22) : style == .minimal ? Color.primary.opacity(0.035) : (design.monochrome ? accent.opacity(0.16) : Color.primary.opacity(0.07)),lineWidth:1) }
    }
}
// Original local vector illustrations, not remote images. No network required.
struct FinamiArt: View {
    var icon:String; var tint:Color; var size:CGFloat = 68
    var body:some View {
        ZStack {
            Circle().fill(tint.opacity(0.09)).frame(width:size,height:size)
            RoundedRectangle(cornerRadius:size*0.26).fill(tint.opacity(0.08)).frame(width:size*0.76,height:size*0.76)
            RoundedRectangle(cornerRadius:size*0.22).fill(LinearGradient(colors:[tint.opacity(0.44),tint.opacity(0.12)],startPoint:.topLeading,endPoint:.bottomTrailing)).frame(width:size*0.67,height:size*0.67).rotationEffect(.degrees(-13))
            Image(systemName:icon).font(.system(size:size*0.36,weight:.semibold)).foregroundStyle(tint)
            
        }.frame(width:size,height:size).accessibilityHidden(true)
    }
}
struct FinamiMetric: View {
    var title:String; var value:String; var tint:Color = .primary
    var body:some View { VStack(alignment:.leading,spacing:6) { Text(title).font(.subheadline).foregroundStyle(.secondary); Text(value).font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(tint).fixedSize(horizontal:false,vertical:true) }.frame(maxWidth:.infinity,alignment:.leading) }
}
struct FinamiMoneyCard: View {
    var title:String; var amount:String; var icon:String; var tint:Color; var subtitle:String
    var body:some View { VStack(alignment:.leading,spacing:12) { HStack { Text(title).font(.headline); Spacer(); FinamiArt(icon:icon,tint:tint,size:56) }; Text(amount).font(.largeTitle.bold()).monospacedDigit().fixedSize(horizontal:false,vertical:true); Text(subtitle).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth:.infinity,alignment:.leading).padding(20).modifier(FinamiCardStyle(tint:tint)) }
}
struct FinamiCreditSummary: View {
    @EnvironmentObject var s:Store
    @Environment(\.finamiMask) private var masked
    var showLimit:Bool; var showUsed:Bool; var showAvailable:Bool
    var dashboardSize: DashboardSize? = nil
    var body:some View { VStack(alignment:.leading,spacing:dashboardSize == .small ? 5 : dashboardSize == .large ? 16 : 10) {
        if dashboardSize == nil || dashboardSize == .large { HStack { Text("Кредитні кошти").font(.headline); Spacer(); FinamiArt(icon:"creditcard.fill",tint:.blue,size:56) } }
        if showLimit { metric("Загальний кредитний ліміт",s.totalCreditLimit,.primary) }
        if showUsed { metric("Використано кредиту",s.totalCreditUsed,.orange) }
        if showAvailable { metric("Доступний кредит",s.totalAvailableCredit,.teal) }
        if !showLimit && !showUsed && !showAvailable { Text("Усі показники приховано").font(.caption) }
        if dashboardSize != .small { Text("Кредит не входить до власних коштів.").font(.caption).foregroundStyle(.secondary) }
    }.padding(dashboardSize == .small ? 5 : dashboardSize == .large ? 20 : 14).frame(maxWidth:.infinity,alignment:.leading).modifier(FinamiCardStyle(tint:.blue)) }
    func metric(_ name:String,_ amount:Int64,_ color:Color)->some View { FinamiMetric(title:name,value:masked ? "••••" : s.displayed(amount),tint:color).padding(dashboardSize == .small ? 5 : dashboardSize == .large ? 14 : 9).background(color.opacity(0.07),in:RoundedRectangle(cornerRadius:14)) }
}
struct FinamiField: View {
    var title:String; @Binding var text:String; var keyboard:UIKeyboardType
    init(_ title:String,text:Binding<String>,keyboard:UIKeyboardType = .default) { self.title=title;self._text=text;self.keyboard=keyboard }
    var body:some View { VStack(alignment:.leading,spacing:5) { Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary); HStack { TextField(title,text:$text).keyboardType(keyboard).accessibilityLabel(title); if !text.isEmpty { Button { text="" } label:{Image(systemName:"xmark.circle.fill").foregroundStyle(.secondary).frame(minWidth:44,minHeight:44)}.buttonStyle(.borderless).accessibilityLabel("Очистити: " + title) } } } }
}
struct FinamiPrivacyNotice: View {
    @EnvironmentObject var s:Store
    var body:some View { VStack(spacing:16) { FinamiArt(icon:"eye.slash",tint:.teal,size:90); Text("Суми приховано").font(.title2.bold()); Text("Вимкни режим приватності, щоб переглянути звіти.").foregroundStyle(.secondary).multilineTextAlignment(.center); Button("Показати суми") { s.changeAppearance { p in p.hideAmounts=false } }.buttonStyle(.borderedProminent) }.padding().navigationTitle("Звіти") }
}
struct FinamiDesignPreview: View {
    var design:FinamiDesign
    var foreground:Color { design.scheme == .dark ? .white : Color(red:0.12,green:0.15,blue:0.19) }
    var background:Color { design.scheme == .dark ? (design.monochrome ? Color(red:0.035,green:0.035,blue:0.045) : Color(red:0.08,green:0.10,blue:0.13)) : Color(red:0.97,green:0.97,blue:0.97) }
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {Text("finami.").font(.headline);Spacer();Image(systemName:"eye").foregroundStyle(design.tint)}
            if [.pure,.graphite,.nord,.cleanLight,.darkClassic,.blackTitanium,.compactPro,.whiteStudio].contains(design) { metric }
            else { HStack(alignment:.center){metric;Spacer(minLength:4);FinamiArt(icon:design == .canvas || design == .rose ? "leaf.fill" : "wallet.pass.fill",tint:design.tint,size:48)} }
            if design == .compactPro {
                previewLine("ПУМБ кредит","Доступно");previewLine("ПУМБ дебет","Власні кошти")
            } else if design == .digitalBank {
                mini("Дебетова картка", "32 450 ₴", "creditcard.fill");mini("Кредитна картка", "65 000 ₴", "creditcard.fill")
            } else if [.pulse,.nord,.graphite,.cleanLight,.darkClassic,.premiumNeon,.blackTitanium,.whiteStudio,.emeraldAnalytics,.liquidGlass].contains(design) {
                HStack(spacing:8){ mini("Власні", "32 450 ₴", "wallet.pass.fill");mini("Кредитні", "65 000 ₴", "creditcard.fill") }
            } else {
                HStack{Image(systemName:"creditcard.fill").foregroundStyle(design.tint);Text("Мої рахунки");Spacer();Image(systemName:"chevron.right")}.font(.caption).padding(10).background(design.tint.opacity(0.09),in:RoundedRectangle(cornerRadius:design.corner/2))
            }
        }.environment(\.font,.system(.body,design:design.font)).padding(14).frame(maxWidth:.infinity,alignment:.leading).foregroundStyle(foreground)
        .background { RoundedRectangle(cornerRadius:design.corner).fill(background);RoundedRectangle(cornerRadius:design.corner).fill(LinearGradient(colors:[design.tint.opacity(design == .pure ? 0.04 : 0.22),design.tint.opacity(0.02)],startPoint:.topLeading,endPoint:.bottomTrailing)) }
    }
    private func previewLine(_ name:String,_ detail:String)->some View { HStack { Image(systemName:"creditcard.fill").foregroundStyle(design.tint);VStack(alignment:.leading){Text(name).font(.subheadline);Text(detail).font(.caption2)};Spacer();Text("••••").font(.headline) }.padding(8).background(design.tint.opacity(0.08),in:RoundedRectangle(cornerRadius:8)) }
    var metric:some View {VStack(alignment:.leading,spacing:4){Text("Власні кошти").font(.caption);Text("32 450 ₴").font(.title2.bold()).monospacedDigit();Text("Без кредитного ліміту").font(.caption2).foregroundStyle(foreground.opacity(0.75))}.frame(maxWidth:.infinity,alignment:.leading)}
    func mini(_ title:String,_ value:String,_ icon:String)->some View { VStack(alignment:.leading,spacing:4){Image(systemName:icon).foregroundStyle(design.tint);Text(title).font(.caption2);Text(value).font(.caption.weight(.semibold)).minimumScaleFactor(0.7)}.frame(maxWidth:.infinity,alignment:.leading).padding(8).background(design.tint.opacity(0.12),in:RoundedRectangle(cornerRadius:design.corner/2)) }
}

struct FinamiHelp:View {
    var body:some View { List {
        Section("Перші кроки") { Label("1. Створи рахунки та введи власні кошти або кредитний борг.",systemImage:"wallet.pass");Label("2. Додай операцію вручну або імпортуй виписку.",systemImage:"plus.circle");Label("3. Налаштуй блоки огляду, видимість сум і дизайн.",systemImage:"slider.horizontal.3");Label("4. Відкрий календар, обери платіж і додай нагадування в деталях.",systemImage:"calendar") }
        Section("Автоматизація — покроково") {NavigationLink {AutomationCenter()} label:{Label("Центр автоматизації та інструкції",systemImage:"bolt.fill")};NavigationLink {BankCenter()} label:{Label("Імпорт виписок і банки",systemImage:"building.columns")}}
        Section("Finami Scan") { NavigationLink { FinamiScanView() } label: { Label("Імпорт зі скриншотів", systemImage: "doc.viewfinder") }; Text("1. Зроби скриншот операції або розстрочки в банку. 2. Обери тип та фото. 3. Перевір суми, дати, рахунок і дублікати. 4. Підтвердь імпорт. Для оновлення розстрочки обери існуючий договір.") }
        Section("Безпека") {Text("Перед оновленням експортуй JSON у Ще → Захист та резервні копії. Не видаляй старий застосунок, якщо хочеш зберегти його дані.");Text("Режим приватності приховує суми на огляді та основних екранах; це не шифрування.")}
    }.navigationTitle("Допомога") }
}

// Native Ukrainian speech recognition; user reviews the draft before saving.
@MainActor final class FinamiSpeech:ObservableObject {
    @Published var text=""; @Published var recording=false; @Published var message=""
    private let audio=AVAudioEngine();private var request:SFSpeechAudioBufferRecognitionRequest?;private var task:SFSpeechRecognitionTask?
    private var installedTap=false
    private var generation=UUID()
    private var starting=false
    func start() async {
        guard !recording && !starting else{return}
        starting=true;let token=UUID();generation=token
        defer { if generation==token { starting=false } }
        let auth=await withCheckedContinuation { (continuation:CheckedContinuation<SFSpeechRecognizerAuthorizationStatus,Never>) in SFSpeechRecognizer.requestAuthorization {continuation.resume(returning:$0)} }
        guard !Task.isCancelled && generation==token else{return}
        guard auth == .authorized else {message="Дозволь розпізнавання мовлення в налаштуваннях iPhone.";return}
        let allowed=await withCheckedContinuation { (continuation:CheckedContinuation<Bool,Never>) in AVAudioSession.sharedInstance().requestRecordPermission{continuation.resume(returning:$0)} }
        guard !Task.isCancelled && generation==token else{return}
        guard allowed else {message="Дозволь мікрофон.";return}
        guard let recognizer=SFSpeechRecognizer(locale:Locale(identifier:"uk-UA")),recognizer.isAvailable else {message="Українське розпізнавання зараз недоступне. Введи текст вручну.";return}
        do { let session=AVAudioSession.sharedInstance();try session.setCategory(.record,mode:.measurement,options:[]);try session.setActive(true)
            let req=SFSpeechAudioBufferRecognitionRequest();req.shouldReportPartialResults=true;req.requiresOnDeviceRecognition=recognizer.supportsOnDeviceRecognition;request=req
            let input=audio.inputNode;let format=input.outputFormat(forBus:0);guard format.sampleRate>0,format.channelCount>0 else {message="Мікрофон недоступний";stop();return}
            input.installTap(onBus:0,bufferSize:1024,format:format){buffer,_ in req.append(buffer)};installedTap=true;audio.prepare();try audio.start();recording=true;message=""
            task=recognizer.recognitionTask(with:req){[weak self] result,error in Task { @MainActor in guard let self=self,self.generation==token else{return};if let result=result{self.text=result.bestTranscription.formattedString};if error != nil || result?.isFinal == true {self.stop()} }}
        } catch {message=error.localizedDescription;stop()}
    }
    func stop(){generation=UUID();starting=false;if audio.isRunning{audio.stop()};if installedTap{audio.inputNode.removeTap(onBus:0);installedTap=false};request?.endAudio();task?.cancel();task=nil;request=nil;recording=false;try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)}
}
struct FinamiVoice:View {
    @EnvironmentObject var s:Store;@StateObject private var speech=FinamiSpeech();@State private var draft:Operation?
    @State private var started = false
    @Environment(\.dismiss) private var dismiss
    var body:some View { NavigationStack { Form { Section {if s.db.preferences?.voiceHideHint != true { HStack(alignment:.top) { Text("Скажи, наприклад: витратив 450 гривень в АТБ.").font(.subheadline); Button { s.changeAppearance { p in p.voiceHideHint=true } } label:{Image(systemName:"xmark.circle.fill")}.buttonStyle(.borderless).accessibilityLabel("Приховати підказку") } } else { Button("Показати підказку") { s.changeAppearance { p in p.voiceHideHint=false } } };Button {if speech.recording{speech.stop()}else{Task{await speech.start()}}} label:{Label(speech.recording ? "Зупинити" : "Почати запис",systemImage:speech.recording ? "stop.circle.fill" : "mic.fill")};if !speech.message.isEmpty {Text(speech.message).foregroundStyle(.orange)};TextEditor(text:$speech.text).frame(minHeight:100);Text("Якщо локальне розпізнавання недоступне, Apple може обробляти мовлення онлайн.").font(.caption)};Button("Підготувати операцію") {speech.stop();let note=speech.text;let kind:Kind=note.lowercased().contains("дохід") || note.lowercased().contains("отримав") ? .income : .expense;let amount=finamiVoiceAmount(note) ?? 0;let account=s.db.accounts.first(where:{!$0.name.isEmpty && $0.code=="UAH" && note.localizedCaseInsensitiveContains($0.name)})?.id ?? s.db.accounts.first(where:{$0.code=="UAH"})?.id ?? cash;draft=Operation(kind:kind,amount:amount,category:suggestedCategory(note,kind:kind,database:s.db),note:note,account:account)}.disabled(speech.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) }.navigationTitle("Голосовий запис").toolbar { ToolbarItem(placement:.cancellationAction){Button("Закрити"){speech.stop();dismiss()}} }.sheet(item:$draft){OpEditor(original:$0)} }.task { if !started { started=true;await speech.start() } }.onDisappear{speech.stop()} }
}

struct FinamiBlockSettings:View {
    @EnvironmentObject var s:Store
    var id:String
    var item:DashboardItem? { DashboardItem.merged(s.db.dashboard).first{$0.id==id} }
    func edit(_ update:(inout DashboardItem)->Void){s.change{d in var all=DashboardItem.merged(d.dashboard);if let i=all.firstIndex(where:{$0.id==id}){update(&all[i])};d.dashboard=all}}
    var body:some View { Form {
        if let item=item {
            Picker("Розмір блоку", selection: Binding(get: { self.item?.size ?? .medium }, set: { v in edit { $0.size = v } })) { ForEach(DashboardSize.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            Toggle("Приховувати суми",isOn:Binding(get:{self.item?.hideAmounts ?? false},set:{v in edit{$0.hideAmounts=v}}))
            Picker("Шаблон",selection:Binding(get:{self.item?.template ?? ""},set:{v in edit{$0.template=v.isEmpty ? nil : v}})){Text("Загальний стиль").tag("");ForEach(FinamiCardTemplate.allCases){Text($0.rawValue).tag($0.rawValue)}}
            Picker("Колір блоку",selection:Binding(get:{self.item?.accentName ?? ""},set:{v in edit{$0.accentName=v.isEmpty ? nil : v}})) { Text("За дизайном").tag(""); ForEach(IzanamiTheme.all) { theme in Text(theme.name).tag(theme.name) } }
            if item.kind == .accounts { NavigationLink("Оформлення та порядок рахунків") { FinamiHomeAccountsSettings() } }
            if item.kind == .creditPortfolio {
                Toggle("Сумарний ліміт",isOn:Binding(get:{self.item?.showLimit ?? true},set:{v in edit{$0.showLimit=v}}))
                Toggle("Використано",isOn:Binding(get:{self.item?.showUsed ?? true},set:{v in edit{$0.showUsed=v}}))
                Toggle("Доступно",isOn:Binding(get:{self.item?.showAvailable ?? true},set:{v in edit{$0.showAvailable=v}}))
            }
            if item.kind == .obligations {
                Toggle("Показувати залишок",isOn:Binding(get:{self.item?.showPaymentRemaining ?? true},set:{v in edit{$0.showPaymentRemaining=v}}))
                Toggle("Показувати дату",isOn:Binding(get:{self.item?.showPaymentDate ?? true},set:{v in edit{$0.showPaymentDate=v}}))
                Toggle("Показувати зображення",isOn:Binding(get:{self.item?.showPaymentImage ?? true},set:{v in edit{$0.showPaymentImage=v}}))
            }
            if [.installments, .subscriptions, .recurring].contains(item.kind) {
                Picker("Кількість записів", selection: Binding(get:{self.item?.categoryCount ?? (item.size == .small ? 1 : item.size == .large ? 6 : 3)},set:{v in edit{$0.categoryCount=v}})) { ForEach([1,2,3,4,5,6,10,20],id:\.self){Text("\($0)").tag($0)} }
                Toggle("Показувати дату",isOn:Binding(get:{self.item?.showPaymentDate ?? true},set:{v in edit{$0.showPaymentDate=v}}))
                Toggle("Показувати загальну суму",isOn:Binding(get:{self.item?.showPaymentTotal ?? true},set:{v in edit{$0.showPaymentTotal=v}}))
                Toggle("Показувати назви платежів",isOn:Binding(get:{self.item?.showPaymentNames ?? true},set:{v in edit{$0.showPaymentNames=v}}))
                if item.kind == .installments { Toggle("Залишок замість планових платежів",isOn:Binding(get:{self.item?.showPaymentRemaining ?? true},set:{v in edit{$0.showPaymentRemaining=v}})) }
            }
            if item.kind == .categories {
                Picker("Кількість категорій",selection:Binding(get:{self.item?.categoryCount ?? 10},set:{v in edit{$0.categoryCount=v}})){ForEach([3,4,5,10,15,30],id:\.self){Text("Топ \($0)").tag($0)}}
                Toggle("Усі категорії",isOn:Binding(get:{self.item?.categorySelection==nil},set:{v in edit{$0.categorySelection=v ? nil : s.db.expenseCategories}}))
                if item.categorySelection != nil {ForEach(s.db.expenseCategories,id:\.self){c in Toggle(c,isOn:Binding(get:{self.item?.categorySelection?.contains(c) ?? false},set:{v in edit{row in var all=row.categorySelection ?? [];all.removeAll{$0==c};if v{all.append(c)};row.categorySelection=all}}))}}
            }
            Section("Перегляд") {DashboardTile(item:item,date:Date())}
        }
    }.navigationTitle("Налаштування блоку") }
}
