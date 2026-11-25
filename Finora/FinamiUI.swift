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
    var id: String { rawValue }
    var tint: Color { switch self { case .signature: return Color(red:0.13,green:0.57,blue:0.40); case .pure: return .blue; case .aurora: return .indigo; case .canvas: return Color(red:0.72,green:0.38,blue:0.23); case .obsidian: return Color(red:0.75,green:0.58,blue:0.25); case .pulse: return .blue; case .nord:return .teal;case .rose:return .pink;case .graphite:return .gray;case .ocean:return .cyan } }
    var corner: CGFloat { switch self { case .pure: return 14; case .canvas: return 30; case .pulse: return 19;case .nord:return 10;case .rose:return 28;case .graphite:return 8;case .ocean:return 26; default: return 24 } }
    var font: Font.Design { self == .canvas || self == .rose ? .rounded : self == .obsidian ? .serif : self == .graphite ? .monospaced : .default }
    var scheme: ColorScheme? { switch self { case .signature,.aurora,.obsidian,.graphite,.ocean:return .dark; case .pure,.canvas,.pulse,.nord,.rose:return .light } }
    var description: String { switch self { case .signature:return "Смарагдовий · м’які картки"; case .pure:return "Світлий · чиста типографіка"; case .aurora:return "Скло · багатошарові фони"; case .canvas:return "Теплі ілюстрації · округлі форми"; case .obsidian:return "Темний · золоті акценти"; case .pulse:return "Банківський · виразні акценти";case .nord:return "Скандинавський · лаконічні плитки";case .rose:return "Пастель · м’які акценти";case .graphite:return "Монохром · компактна типографіка";case .ocean:return "Океан · глибокі градієнти" } }
}
enum FinamiCardTemplate: String, CaseIterable, Identifiable {
    case automatic = "За дизайном", gradient = "Gradient", minimal = "Minimal", glass = "Glass", soft = "Soft", bank = "Bank", neon = "Neon", stripe = "Stripe", compact = "Compact", illustrated = "Illustrated", premium = "Premium"
    var id:String { rawValue }
}
struct FinamiCardStyle: ViewModifier {
    @EnvironmentObject var s: Store
    var tint: Color
    var template: String? = nil
    func body(content: Content) -> some View {
        let design = FinamiDesign(rawValue:s.db.preferences?.design ?? "Signature") ?? .signature
        let style = FinamiCardTemplate(rawValue:template ?? s.db.preferences?.cardTemplate ?? "За дизайном") ?? .automatic
        let radius = style == .minimal || style == .compact ? 12 : design.corner
        content.background {
            ZStack(alignment:.leading) {
                RoundedRectangle(cornerRadius:radius).fill(Color(uiColor:.secondarySystemGroupedBackground))
                if style == .glass || (style == .automatic && design == .aurora) { RoundedRectangle(cornerRadius:radius).fill(.regularMaterial); RoundedRectangle(cornerRadius:radius).fill(tint.opacity(0.12)) }
                else if [.gradient,.premium,.bank,.illustrated].contains(style) || (style == .automatic && [.signature,.pulse,.obsidian,.ocean].contains(design)) { RoundedRectangle(cornerRadius:radius).fill(LinearGradient(colors:[tint.opacity(0.24),tint.opacity(0.035)],startPoint:.topLeading,endPoint:.bottomTrailing)) }
                else if style == .soft || (style == .automatic && [.canvas,.rose,.nord].contains(design)) { RoundedRectangle(cornerRadius:radius).fill(tint.opacity(0.12)) }
                if style == .stripe { Capsule().fill(tint).frame(width:4).padding(.vertical,12) }
            }
        }.clipShape(RoundedRectangle(cornerRadius:radius)).overlay { if style == .neon { RoundedRectangle(cornerRadius:radius).stroke(tint.opacity(0.6),lineWidth:1) } }.shadow(color:style == .premium ? tint.opacity(0.14) : .clear,radius:12,y:5)
    }
}
// Original local vector illustrations, not remote images. No network required.
struct FinamiArt: View {
    var icon:String; var tint:Color; var size:CGFloat = 68
    var body:some View {
        ZStack {
            Circle().fill(tint.opacity(0.09)).frame(width:size,height:size)
            Circle().fill(tint.opacity(0.18)).frame(width:size*0.76,height:size*0.76).offset(x:-size*0.08,y:size*0.04)
            RoundedRectangle(cornerRadius:size*0.22).fill(LinearGradient(colors:[tint.opacity(0.44),tint.opacity(0.12)],startPoint:.topLeading,endPoint:.bottomTrailing)).frame(width:size*0.67,height:size*0.67).rotationEffect(.degrees(-13))
            Image(systemName:icon).font(.system(size:size*0.36,weight:.semibold)).foregroundStyle(tint).shadow(color:tint.opacity(0.25),radius:4,y:3)
            Circle().fill(tint.opacity(0.45)).frame(width:size*0.11,height:size*0.11).offset(x:size*0.37,y:-size*0.29)
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
    var body:some View { VStack(alignment:.leading,spacing:14) {
        HStack { Text("Кредитні кошти").font(.headline); Spacer(); FinamiArt(icon:"creditcard.fill",tint:.blue,size:56) }
        if showLimit { metric("Загальний кредитний ліміт",s.totalCreditLimit,.primary) }
        if showUsed { metric("Використано кредиту",s.totalCreditUsed,.orange) }
        if showAvailable { metric("Доступний кредит",s.totalAvailableCredit,.teal) }
        if !showLimit && !showUsed && !showAvailable { Text("Усі показники приховано").font(.caption) }
        Text("Кредит не входить до власних коштів.").font(.caption).foregroundStyle(.secondary)
    }.padding(18).frame(maxWidth:.infinity,alignment:.leading).modifier(FinamiCardStyle(tint:.blue)) }
    func metric(_ name:String,_ amount:Int64,_ color:Color)->some View { FinamiMetric(title:name,value:masked ? "••••" : s.displayed(amount),tint:color).padding(12).background(color.opacity(0.07),in:RoundedRectangle(cornerRadius:14)) }
}
struct FinamiField: View {
    var title:String; @Binding var text:String; var keyboard:UIKeyboardType
    init(_ title:String,text:Binding<String>,keyboard:UIKeyboardType = .default) { self.title=title;self._text=text;self.keyboard=keyboard }
    var body:some View { VStack(alignment:.leading,spacing:5) { Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary); HStack { TextField(title,text:$text).keyboardType(keyboard).accessibilityLabel(title); if !text.isEmpty { Button { text="" } label:{Image(systemName:"xmark.circle.fill").foregroundStyle(.secondary).frame(minWidth:44,minHeight:44)}.buttonStyle(.borderless).accessibilityLabel("Очистити: " + title) } } } }
}
struct FinamiPrivacyNotice: View {
    @EnvironmentObject var s:Store
    var body:some View { VStack(spacing:16) { FinamiArt(icon:"eye.slash",tint:.teal,size:90); Text("Суми приховано").font(.title2.bold()); Text("Вимкни режим приватності, щоб переглянути звіти.").foregroundStyle(.secondary).multilineTextAlignment(.center); Button("Показати суми") { s.change { d in var p=d.preferences ?? .init();p.hideAmounts=false;d.preferences=p } }.buttonStyle(.borderedProminent) }.padding().navigationTitle("Звіти") }
}
struct FinamiDesignPreview: View {
    var design:FinamiDesign
    var foreground:Color { design.scheme == .dark ? .white : Color(red:0.12,green:0.15,blue:0.19) }
    var background:Color { design.scheme == .dark ? Color(red:0.08,green:0.10,blue:0.13) : Color(red:0.97,green:0.97,blue:0.97) }
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {Text("finami.").font(.headline);Spacer();Image(systemName:"eye").foregroundStyle(design.tint)}
            if [.pure,.graphite,.nord].contains(design) { metric }
            else { HStack(alignment:.center){metric;Spacer(minLength:4);FinamiArt(icon:design == .canvas || design == .rose ? "leaf.fill" : "wallet.pass.fill",tint:design.tint,size:48)} }
            if [.pulse,.nord,.graphite].contains(design) {
                HStack(spacing:8){ mini("Власні", "32 450 ₴", "wallet.pass.fill");mini("Кредитні", "65 000 ₴", "creditcard.fill") }
            } else {
                HStack{Image(systemName:"creditcard.fill").foregroundStyle(design.tint);Text("Мої рахунки");Spacer();Image(systemName:"chevron.right")}.font(.caption).padding(10).background(design.tint.opacity(0.09),in:RoundedRectangle(cornerRadius:design.corner/2))
            }
        }.environment(\.font,.system(.body,design:design.font)).padding(14).frame(maxWidth:.infinity,alignment:.leading).foregroundStyle(foreground)
        .background { RoundedRectangle(cornerRadius:design.corner).fill(background);RoundedRectangle(cornerRadius:design.corner).fill(LinearGradient(colors:[design.tint.opacity(design == .pure ? 0.04 : 0.22),design.tint.opacity(0.02)],startPoint:.topLeading,endPoint:.bottomTrailing)) }
    }
    var metric:some View {VStack(alignment:.leading,spacing:4){Text("Власні кошти").font(.caption);Text("32 450 ₴").font(.title2.bold()).monospacedDigit();Text("Без кредитного ліміту").font(.caption2).foregroundStyle(foreground.opacity(0.75))}.frame(maxWidth:.infinity,alignment:.leading)}
    func mini(_ title:String,_ value:String,_ icon:String)->some View { VStack(alignment:.leading,spacing:4){Image(systemName:icon).foregroundStyle(design.tint);Text(title).font(.caption2);Text(value).font(.caption.weight(.semibold)).minimumScaleFactor(0.7)}.frame(maxWidth:.infinity,alignment:.leading).padding(8).background(design.tint.opacity(0.12),in:RoundedRectangle(cornerRadius:design.corner/2)) }
}

struct FinamiPayment: Identifiable {
    var id:String; var name:String; var kind:String; var date:Date; var amount:Int64; var currency:String; var remaining:Int64?; var subscription:Bool
    var overdue:Bool { Calendar.current.startOfDay(for:date) < Calendar.current.startOfDay(for:Date()) }
}
extension Store {
    var upcomingPayments:[FinamiPayment] {
        let debts = db.obligations.filter { $0.remaining > 0 && [.installment,.owe,.recurring].contains($0.kind) }.map { o in FinamiPayment(id:o.id,name:o.name,kind:o.kind.title,date:o.due,amount:o.monthly > 0 ? min(o.monthly,o.remaining) : o.remaining,currency:"UAH",remaining:o.remaining,subscription:false) }
        let subs = (db.subscriptions ?? []).filter(\.active).map { r in FinamiPayment(id:r.id,name:r.name,kind:"Підписка",date:r.next,amount:r.amount,currency:r.currency,remaining:nil,subscription:true) }
        return (debts+subs).sorted { $0.date < $1.date }
    }
    func scheduledThisMonth(currency: String, now: Date = Date()) -> Int64 {
        let cal = Calendar.current
        guard let end = cal.dateInterval(of: .month, for: now)?.end else { return 0 }
        let start = cal.startOfDay(for: now)
        var total: Int64 = 0
        for p in upcomingPayments where p.currency == currency {
            let period = p.subscription ? db.subscriptions?.first(where: {$0.id == p.id})?.period : nil
            total += finamiScheduledAmounts(start:p.date, amount:p.amount, remaining:p.remaining, component:period?.component ?? .month, step:period?.step ?? 1, from:start, until:end, calendar:cal).reduce(0,+)
        }
        return total
    }
    // A confirmation records the obligation/subscription only; bank imports remain the source of actual expenses.
    func confirmPayment(_ payment:FinamiPayment) -> Bool {
        guard let live=upcomingPayments.first(where:{$0.id==payment.id}),live.date==payment.date,live.amount==payment.amount,live.amount>0 else {error="Платіж уже змінено. Відкрий його знову.";return false}
        let previous=(db.reminders ?? []).filter{$0.linkedID==payment.id}
        var renewed:[PersonalReminder]=[]
        let ok=change { d in
            var next:Date?=nil
            if payment.subscription,let i=d.subscriptions?.firstIndex(where:{$0.id==payment.id}),var r=d.subscriptions?[i] {
                let end=Calendar.current.date(byAdding:r.period.component,value:r.period.step,to:r.next) ?? r.next
                r.payments.append(.init(date:Date(),amount:payment.amount,currency:payment.currency,through:end));r.next=end;d.subscriptions?[i]=r;next=end
            } else if let i=d.obligations.firstIndex(where:{$0.id==payment.id}) {
                d.obligations[i].paid+=payment.amount
                if d.obligations[i].remaining>0 {d.obligations[i].due=shift(d.obligations[i].due,1);next=d.obligations[i].due}
            }
            d.reminders?.removeAll{$0.linkedID==payment.id}
            if let next=next { for r in previous { var copy=r;copy.date=next.addingTimeInterval(r.date.timeIntervalSince(payment.date)); if copy.date>Date() {renewed.append(copy)} };d.reminders=(d.reminders ?? [])+renewed }
        }
        if ok {previous.forEach{ReminderScheduler.cancel($0)};let scheduled=renewed;Task { @MainActor in for r in scheduled { do {try await ReminderScheduler.schedule(r)} catch {self.error="Платіж збережено. Нагадування: "+error.localizedDescription} } }}
        return ok
    }
}
struct FinamiPaymentCard:View {
    @EnvironmentObject var s:Store
    @Environment(\.finamiMask) private var masked
    var payment:FinamiPayment
    var showRemaining = true
    var showDate = true
    var showImage = true
    var body:some View { VStack(alignment:.leading,spacing:12) {
        HStack(alignment:.top) { VStack(alignment:.leading,spacing:5) { Text(payment.kind).font(.caption).foregroundStyle(.secondary);Text(payment.name).font(.headline).fixedSize(horizontal:false,vertical:true) };Spacer(minLength:8);if showImage { if let data=s.db.paymentPhotos?[payment.id],let image=UIImage(data:data) {Image(uiImage:image).resizable().scaledToFill().frame(width:62,height:62).clipShape(RoundedRectangle(cornerRadius:14)).accessibilityHidden(true)}else{FinamiArt(icon:payment.subscription ? "repeat" : "calendar.badge.clock",tint:.indigo,size:62)} } }
        Text(masked ? "••••" : s.visibleMoney(payment.amount,payment.currency)).font(.largeTitle.bold()).monospacedDigit().fixedSize(horizontal:false,vertical:true)
        if showDate { Label(payment.date.formatted(date:.abbreviated,time:.omitted),systemImage:"calendar").foregroundStyle(payment.overdue ? Color.orange : Color.secondary) }
        if payment.overdue {Label("Прострочено",systemImage:"exclamationmark.circle").font(.caption).foregroundStyle(.orange)}
        if showRemaining, let remaining=payment.remaining {FinamiMetric(title:"Залишок",value:masked ? "••••" : s.visibleMoney(remaining))}
        HStack {Text("Деталі платежу").font(.subheadline.weight(.medium));Spacer();Image(systemName:"chevron.right")}.foregroundStyle(.tint)
    }.padding(16).frame(maxWidth:.infinity,alignment:.leading).modifier(FinamiCardStyle(tint:.indigo)) }
}
struct FinamiMonthPayments:View {
    @EnvironmentObject var s:Store
    @Environment(\.finamiMask) private var masked
    var body:some View { VStack(alignment:.leading,spacing:8) {Text("Заплановано до кінця місяця").font(.headline);ForEach(["UAH","USD"],id:\.self) { currency in let total=s.scheduledThisMonth(currency:currency); if total>0 || currency=="UAH" {Text(masked ? "••••" : s.visibleMoney(total,currency)).font(.title.bold()).monospacedDigit()} };Text("Прогноз за графіком; прострочені платежі показано окремо.").font(.caption).foregroundStyle(.secondary) }.padding(16).frame(maxWidth:.infinity,alignment:.leading).modifier(FinamiCardStyle(tint:.indigo)) }
}
struct FinamiPaymentDetails:View {
    @EnvironmentObject var s:Store; @Environment(\.dismiss) var dismiss
    var payment:FinamiPayment
    @State private var photo:PhotosPickerItem?
    @State private var confirm=false
    var body:some View { NavigationStack { Form {
        Section {FinamiPaymentCard(payment:payment)}
        Section("Керування") {
            Button("Позначити сплаченим") {confirm=true}
            if payment.subscription,let r=s.db.subscriptions?.first(where:{$0.id==payment.id}) {NavigationLink("Редагувати підписку") {SubscriptionEditor(original:r)}}
            else if let o=s.db.obligations.first(where:{$0.id==payment.id}) {NavigationLink("Редагувати платіж / дату") {ObligationEditor(original:o)}}
            PhotosPicker(selection:$photo,matching:.images) {Label("Вибрати фотографію",systemImage:"photo")}
            if s.db.paymentPhotos?[payment.id] != nil {Button("Видалити фотографію",role:.destructive){s.change{$0.paymentPhotos?.removeValue(forKey:payment.id)}}}
        }
        Section("Нагадування") {
            ForEach((s.db.reminders ?? []).filter{$0.linkedID==payment.id}) {r in NavigationLink {ReminderEditor(original:r)} label:{Label(r.date.formatted(date:.abbreviated,time:.shortened),systemImage:r.enabled ? "bell.fill" : "bell.slash")}}
            .onDelete { offsets in let all=(s.db.reminders ?? []).filter{$0.linkedID==payment.id};let ids=offsets.map{all[$0]};if s.change({d in d.reminders?.removeAll{r in ids.contains{$0.id==r.id}}}){ids.forEach{ReminderScheduler.cancel($0)}} }
            NavigationLink {ReminderEditor(original:.init(title:payment.name,date:max(Date().addingTimeInterval(3600),payment.date.addingTimeInterval(-86400)),linkedID:payment.id,hideDetails:true))} label:{Label("Додати нагадування",systemImage:"bell.badge")}
            Text("Можна створити кілька нагадувань із власними датою та часом.").font(.caption)
        }
    }.navigationTitle("Деталі платежу").toolbar{ToolbarItem(placement:.cancellationAction){Button("Готово"){dismiss()}}}.confirmationDialog("Позначити платіж сплаченим?",isPresented:$confirm){Button("Підтвердити оплату"){if s.confirmPayment(payment){dismiss()}};Button("Скасувати",role:.cancel){} } message:{Text("Оновлює залишок і дату, але не створює банківську операцію повторно.")}
        .onChange(of:photo) { item in guard let item=item else{return};Task { @MainActor in if let data=try? await item.loadTransferable(type:Data.self),let image=UIImage(data:data) { let size=image.size;guard size.width>0,size.height>0 else{return};let factor=min(1,800/max(size.width,size.height));let resized=UIGraphicsImageRenderer(size:CGSize(width:size.width*factor,height:size.height*factor)).image{_ in image.draw(in:CGRect(x:0,y:0,width:size.width*factor,height:size.height*factor))};if let jpeg=resized.jpegData(compressionQuality:0.75){s.change{d in var all=d.paymentPhotos ?? [:];all[payment.id]=jpeg;d.paymentPhotos=all}} } } }
    } }
}
struct FinamiHelp:View {
    var body:some View { List {
        Section("Перші кроки") { Label("1. Створи рахунки та введи власні кошти або кредитний борг.",systemImage:"wallet.pass");Label("2. Додай операцію вручну або імпортуй виписку.",systemImage:"plus.circle");Label("3. Налаштуй блоки огляду, видимість сум і дизайн.",systemImage:"slider.horizontal.3");Label("4. Відкрий календар, обери платіж і додай нагадування в деталях.",systemImage:"calendar") }
        Section("Автоматизація — покроково") {NavigationLink {AutomationCenter()} label:{Label("Центр автоматизації та інструкції",systemImage:"bolt.fill")};NavigationLink {BankCenter()} label:{Label("Імпорт виписок і банки",systemImage:"building.columns")}}
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
    var body:some View { NavigationStack { Form { Section {if s.db.preferences?.voiceHideHint != true { HStack(alignment:.top) { Text("Скажи, наприклад: витратив 450 гривень в АТБ.").font(.subheadline); Button { s.change { d in var p=d.preferences ?? .init();p.voiceHideHint=true;d.preferences=p } } label:{Image(systemName:"xmark.circle.fill")}.buttonStyle(.borderless).accessibilityLabel("Приховати підказку") } } else { Button("Показати підказку") { s.change { d in var p=d.preferences ?? .init();p.voiceHideHint=false;d.preferences=p } } };Button {if speech.recording{speech.stop()}else{Task{await speech.start()}}} label:{Label(speech.recording ? "Зупинити" : "Почати запис",systemImage:speech.recording ? "stop.circle.fill" : "mic.fill")};if !speech.message.isEmpty {Text(speech.message).foregroundStyle(.orange)};TextEditor(text:$speech.text).frame(minHeight:100);Text("Якщо локальне розпізнавання недоступне, Apple може обробляти мовлення онлайн.").font(.caption)};Button("Підготувати операцію") {speech.stop();let note=speech.text;let kind:Kind=note.lowercased().contains("дохід") || note.lowercased().contains("отримав") ? .income : .expense;let amount=finamiVoiceAmount(note) ?? 0;let account=s.db.accounts.first(where:{!$0.name.isEmpty && $0.code=="UAH" && note.localizedCaseInsensitiveContains($0.name)})?.id ?? s.db.accounts.first(where:{$0.code=="UAH"})?.id ?? cash;draft=Operation(kind:kind,amount:amount,category:suggestedCategory(note,kind:kind,database:s.db),note:note,account:account)}.disabled(speech.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) }.navigationTitle("Голосовий запис").toolbar { ToolbarItem(placement:.cancellationAction){Button("Закрити"){speech.stop();dismiss()}} }.sheet(item:$draft){OpEditor(original:$0)} }.task { if !started { started=true;await speech.start() } }.onDisappear{speech.stop()} }
}

struct FinamiBlockSettings:View {
    @EnvironmentObject var s:Store
    var id:String
    var item:DashboardItem? { DashboardItem.merged(s.db.dashboard).first{$0.id==id} }
    func edit(_ update:(inout DashboardItem)->Void){s.change{d in var all=DashboardItem.merged(d.dashboard);if let i=all.firstIndex(where:{$0.id==id}){update(&all[i])};d.dashboard=all}}
    var body:some View { Form {
        if let item=item {
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
            if item.kind == .categories {
                Picker("Кількість категорій",selection:Binding(get:{self.item?.categoryCount ?? 10},set:{v in edit{$0.categoryCount=v}})){ForEach([3,4,5,10,15,30],id:\.self){Text("Топ \($0)").tag($0)}}
                Toggle("Усі категорії",isOn:Binding(get:{self.item?.categorySelection==nil},set:{v in edit{$0.categorySelection=v ? nil : s.db.expenseCategories}}))
                if item.categorySelection != nil {ForEach(s.db.expenseCategories,id:\.self){c in Toggle(c,isOn:Binding(get:{self.item?.categorySelection?.contains(c) ?? false},set:{v in edit{row in var all=row.categorySelection ?? [];all.removeAll{$0==c};if v{all.append(c)};row.categorySelection=all}}))}}
            }
            Section("Перегляд") {DashboardTile(item:item,date:Date())}
        }
    }.navigationTitle("Налаштування блоку") }
}
