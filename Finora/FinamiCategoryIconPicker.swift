import SwiftUI

struct FinamiCategoryIconPicker: View {
    @Binding var name:String
    @Environment(\.dismiss) private var dismiss
    @State private var query=""
    private let groups:[(String,String)] = [
        ("Їжа продукти кафе напої food drink", "🛒 🛍️ 🥑 🍎 🍐 🍊 🍌 🍇 🍓 🥝 🍉 🍒 🍍 🥭 🍋 🍅 🥒 🥕 🌽 🥦 🥬 🧅 🥔 🍄 🍞 🥐 🥖 🥨 🧀 🥚 🍳 🥞 🧇 🥓 🥩 🍗 🍖 🌭 🍔 🍟 🍕 🥪 🌮 🌯 🥙 🧆 🍜 🍝 🍣 🍱 🍲 🥗 🍚 🍙 🍤 🥟 🍿 🍩 🍪 🎂 🍰 🧁 🍫 🍬 🍭 🍦 🍨 🥛 ☕ 🍵 🧋 🧃 🥤 🍺 🍻 🍷 🥂 🍸 🍹 🧊 🍽️ 🥄"),
        ("Транспорт авто подорожі таксі travel transport", "🚗 🚕 🚙 🚌 🚎 🏎️ 🚓 🚑 🚒 🚐 🛻 🚚 🚛 🚜 🏍️ 🛵 🚲 🛴 🛹 🛼 🚆 🚇 🚈 🚉 🚊 🚝 🚄 🚅 🚂 ✈️ 🛫 🛬 🚁 🚀 🛳️ ⛴️ 🚢 ⛵ 🛶 ⚓ ⛽ 🅿️ 🚏 🚦 🛣️ 🗺️ 🧭 🧳 🎫 🏨 🏕️"),
        ("Дім комунальні покупки одяг ремонт home shopping", "🏠 🏡 🏢 🏘️ 🏗️ 🛠️ 🔧 🔨 🪛 🪚 🔩 ⚙️ 🧰 🪜 🧱 🪟 🚪 🛋️ 🪑 🛏️ 🛌 🧸 🪞 🪴 🏺 🧹 🧺 🧼 🧽 🪣 🚿 🛁 🚽 🧻 🪥 💡 🔌 🔋 🕯️ 🧯 💧 🚰 🔥 🌡️ 🧊 👕 👔 👖 🧥 🧤 🧣 🧦 👗 👚 👙 👟 👞 🥾 🥿 👠 🧢 🎩 👒 🎒 👜 👛 💼 🕶️ 👓 ⌚ 💍 💎 🧵 🪡 🧶"),
        ("Здоров'я спорт краса тварини health sport pets", "💊 💉 🩺 🩹 🩻 🏥 ⚕️ 🧬 🦷 🦴 👁️ 👂 🫀 🫁 🧠 ❤️ 💪 🏋️ 🤸 🧘 🏃 🚶 🏊 🚴 🏄 🧗 🤾 ⛹️ 🏌️ 🤺 🏇 ⚽ 🏀 🏈 ⚾ 🎾 🏐 🏉 🥏 🎱 🏓 🏸 🥊 🥋 🏒 🏑 ⛳ 🏹 🎯 ⛸️ 🛷 🏂 ⛷️ 🥇 🏅 🏆 🥈 🥉 💇 💅 💄 🪮 🧴 🪒 🐾 🐕 🐈 🐩 🐇 🐹 🐠 🐟 🐢 🦜 🐦 🐎 🦮 🐕‍🦺"),
        ("Розваги техніка навчання послуги entertainment education tech", "🎮 🕹️ 🎲 🧩 ♟️ 🎨 🖌️ 🖍️ 🎭 🎬 🎥 📽️ 🎞️ 📺 📷 📸 📹 🎧 🎤 🎙️ 🎚️ 🎛️ 🎹 🎸 🎻 🎺 🎷 🥁 🪘 🎼 🎵 🎶 📱 ☎️ 📞 💻 🖥️ ⌨️ 🖱️ 🖨️ 🖲️ 💾 💿 📀 📡 📻 🔊 🔇 🔔 📶 🌐 🛰️ 🧑‍💻 📚 📖 📕 📗 📘 📙 📔 📒 📓 📝 ✏️ 🖊️ 🖋️ 📐 📏 🧮 🔬 🔭 🧪 🧫 🎓 🎒 🏫 🧑‍🏫 🎁 🎈 🎉 🎊 🎀 🎄 🎃 🎆 🎇 🪩 🏖️ 🏞️"),
        ("Фінанси зарплата документи інше finance money work", "💰 💵 💶 💷 💴 🪙 💳 🏦 🏧 💸 💲 🧾 📊 📈 📉 💹 🧮 🗃️ 🗄️ 📁 📂 🗂️ 🗒️ 📋 📌 📍 📎 🖇️ 🗓️ 📅 ⏰ ⏱️ ⏳ 🔑 🔐 🔒 🔓 🛡️ ⚖️ 📜 📄 📑 📃 ✉️ 📩 📦 📮 📬 📨 🏷️ 🏛️ 🏪 🏬 🏭 🧑‍🔧 🧑‍🍳 🧑‍⚕️ 👨‍👩‍👧 🍼 👶 🧒 👴 👵 🌱 🌷 🌹 🌻 🌿 🍀 🌲 🌳 🌴 🌵 🌍 🌙 ☀️ ⭐ ✨ ⚡ ☔ ❄️ ☁️ 🌈 ♻️ ✅ ❗ ❓ ➕ ➖ 🔄 🔁 🔖 🏴")
    ]
    var body:some View {
        ScrollView { LazyVStack(alignment:.leading,spacing:14) {
            ForEach(groups.indices,id:\.self) { i in
                if FinamiSearchPolicy.matches(query,text:groups[i].0+" "+groups[i].1) {
                    Text(groups[i].0.components(separatedBy:" ").prefix(3).joined(separator:" ")).font(.headline)
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:48),spacing:8)],spacing:8) {
                        ForEach(Array(Set(groups[i].1.split(separator:" ").map(String.init))).sorted(),id:\.self) { icon in
                            Button { name=FinamiSearchPolicy.categoryName(name,icon:icon);dismiss() } label:{Text(icon).font(.title2).frame(minWidth:44,minHeight:44).frame(maxWidth:.infinity).background(Color(uiColor:.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:10))}.buttonStyle(.plain).accessibilityLabel(icon)
                        }
                    }
                }
            }
        }.padding() }.navigationTitle("Іконки категорій").searchable(text:$query,placement:.navigationBarDrawer(displayMode:.always),prompt:"Їжа, спорт, транспорт…")
    }
}
