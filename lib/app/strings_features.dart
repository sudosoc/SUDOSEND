// Strings for the optional features (v0.7): the Features page, the (i)
// explanations, messages, folder sync, speed test and previews.

const Map<String, Map<String, String>> featureStrings = {
  'en': {
    'tab_messages': 'Messages',
    'close': 'Close',
    'got_it': 'Got it',
    'more_info': 'What is this?',
    'online': 'Online',
    'device_actions': 'More',
    'act_message': 'Send a message',

    // Settings categories
    's_features': 'Features',
    's_features_sub': 'Switch any extra on or off · tap (i) to see what it does',
    'cat_device_sub': 'Name, fingerprint, where the key is kept',
    'cat_receiving_sub': 'Save folder, auto-accept, notifications, speed cap',
    'cat_privacy_sub': 'Stealth, trusted and blocked devices, audit log',
    'cat_usage_sub': 'How much you sent and received, per device',
    'cat_appearance_sub': 'Language and visual effects',
    'cat_about_sub': 'Version, protocol, source code, license',
    'fg_transfer': 'Transfers',
    'fg_devices': 'Between your devices',
    'fg_noapp': 'Devices without the app',

    // Feature switches
    'f_compression': 'Smart compression',
    'f_compression_sub': 'Squeezes text, code, logs and documents on the fly.',
    'f_previews_send': 'Send image previews',
    'f_previews_send_sub': 'Attach small thumbnails so the other side sees what is coming.',
    'f_previews_show': 'Show image previews',
    'f_previews_show_sub': 'Show the thumbnails other devices attach before you accept.',
    'f_queue': 'Send when online',
    'f_queue_sub': 'Queue files for a trusted device that is off right now.',
    'f_chat': 'Messages',
    'f_chat_sub': 'Quick encrypted texts with trusted devices, kept as threads.',
    'f_sync': 'Folder sync',
    'f_sync_sub': 'Keep a folder identical on two trusted devices, both ways.',
    'f_speed': 'Allow speed tests',
    'f_speed_sub': 'Let trusted devices measure the real speed to this one.',
    'f_web': 'Browser share',
    'f_web_sub': 'Send to and receive from any device with a browser.',

    // (i) explanations
    'i_compression':
        'Before each 256 KB piece is encrypted, SUDOSEND tries to compress it. If it shrinks by at least 10% the compressed piece is sent, otherwise the original. Files that are already compressed (photos, videos, ZIP, APK, PDF, Office files) are skipped, and after 3 pieces that do not shrink it stops trying for that file.\n\nResult: text, logs, source code, CSV, databases and uncompressed images arrive much faster on slow Wi-Fi. The SHA-256 check is done on the original data, so nothing can be lost.\n\nBoth devices must have it on. Turn it off if this device has a very weak CPU and a very fast network.',
    'i_previews_send':
        'When you send photos, SUDOSEND makes a tiny thumbnail (max 96 KB, up to 8 images) and attaches it to the request, so the receiver can see the pictures before accepting.\n\nThumbnails travel inside the same encrypted channel. Turn this off if you do not want the content to be visible before the other person accepts.',
    'i_previews_show':
        'Shows the thumbnails a sender attached in the "incoming" dialog, so you know what you are accepting.\n\nThe images are decoded by the system image decoder. If you only accept files from people you know, leave it on. If you are on an untrusted network and want the smallest attack surface, turn it off.',
    'i_queue':
        'Shows your trusted devices that are offline under the device list. Tap one to queue the current selection; it is sent automatically (with retries) the moment that device appears on the network.\n\nTurning this off hides the option; items already queued are still delivered.',
    'i_chat':
        'Adds a Messages tab. Send short texts to trusted devices — links, codes, notes — with the same end-to-end encryption as files. Messages from trusted devices arrive without a prompt; from other devices you are asked first.\n\nThreads are kept only on this device (in the app folder), up to 500 messages per device. You can clear a thread at any time. Turning this off hides the tab; texts then arrive like normal text transfers.',
    'i_sync':
        'Keeps a folder the same on two trusted devices. Every minute (and whenever the other device comes online) each side asks the other for its file list and sends the files that are new or newer. Both sides doing this gives two-way sync.\n\nSafety rules:\n• Only between trusted devices.\n• Newest change wins; the older copy is moved to ".sudosend-archive" inside the folder — never deleted.\n• Deleting a file is NOT synced, so a mistake on one device can never wipe the other.\n• Hidden files and folders (starting with ".") are skipped.\n\nStart it from a device\'s "More" menu or from "Manage sync folders". Not available on iOS.',
    'i_speed':
        'A speed test streams random data for 6 seconds through the real encrypted channel and reports what actually arrived — the speed your transfers will really get, not a Wi-Fi link-rate number.\n\nWith this on, trusted devices may run a test against this device; it writes nothing to disk. Untrusted devices are always refused. You can start a test yourself from any trusted device\'s "More" menu.',
    'i_web':
        'Lets any phone, laptop or TV with a browser download from you or upload to you — no app needed. You get a private link (and QR code) with a random token, an optional PIN, an expiry time and an optional download limit.\n\nThis traffic is plain HTTP on your local network (browsers cannot speak the Wraith protocol), so use the PIN on shared Wi-Fi. Turning this off hides the buttons and stops any running share.',
    'i_sender_folders':
        'Puts files from each device in its own sub-folder, for example "SUDOSEND/Seif-Laptop/". Handy when several devices send to you.',
    'i_auto_accept':
        'Files from devices you have marked as trusted are accepted without asking. Unknown devices are always asked, with the 6-digit code to compare.\n\nLeave off if other people sometimes use your trusted devices.',
    'i_auto_copy':
        'When someone sends you a text, it is copied to your clipboard right away so you can paste it.',
    'i_background':
        'Keeps a small notification so Android does not stop SUDOSEND, so you can receive while the app is closed. Uses a little more battery.',
    'i_notifications':
        'Shows a notification for incoming requests (with Accept / Decline buttons on Android), finished transfers and new messages.',
    'i_speed_limit':
        'Caps how fast this device sends. Everything stays local — this is not about internet data. It is about Wi-Fi airtime: a big transfer can make video calls or games lag for everyone on the same router. Set a cap to stay polite; "No limit" is fastest.',
    'i_hot':
        'Creates "SUDOSEND Outbox" in your home folder with one folder per trusted device. Anything you drop in is sent to that device automatically when it is online, then moved to "Sent". Good for scripts and quick drag-and-drop.',
    'i_clip_sync':
        'Copy on one device, paste on another. The clipboard is sent only to trusted devices, encrypted. On phones the OS allows reading the clipboard only while SUDOSEND is open.\n\nCareful: passwords you copy are synced too.',
    'i_ring':
        'Lets your trusted devices make this one ring loudly — even on silent — to find it. Only trusted devices can do this.',
    'i_stealth':
        'This device stops announcing itself. Others will not see it in their list, but it still answers devices it already trusts, and you can still send from it. Useful on public Wi-Fi.',
    'i_trusted':
        'Devices you trusted (after comparing the 6-digit code or scanning a QR). Their identity key is pinned: if someone else pretends to be them, the transfer is blocked. Revoke a device if you lose it.',
    'i_blocked':
        'Devices you blocked. Their requests are refused silently without a prompt.',
    'i_audit':
        'A log of every finished transfer (names, sizes, devices, times — never message contents). Export it as JSON for records or audits.',
    'i_rejected':
        'Connections refused by the built-in flood protection or the block list since the app started. A large number on a home network can mean something is probing your device.',
    'i_effects':
        'Full: live glass blur and animated background (needs a good GPU). Balanced: the same look without live blur — smooth on most devices. Lite: no shadows or animations, best for Raspberry Pi, old phones and TVs.',
    'i_key_storage':
        'Where this device\'s private identity key is kept. Android Keystore and Windows DPAPI encrypt it with a key the OS protects, so copying the app folder to another machine does not copy your identity.',

    // Messages
    'chat_empty': 'No messages yet',
    'chat_empty_sub': 'Trust a device (compare the code or scan its QR) to start messaging it.',
    'chat_new': 'Start a conversation',
    'chat_start': 'Tap to send a message',
    'chat_hint': 'Message',
    'chat_offline': 'Offline',
    'chat_from': 'Message from {name}',
    'chat_retry': 'tap to retry',
    'chat_clear': 'Clear conversation',
    'chat_clear_confirm': 'Delete all messages with this device from this device?',
    'incoming_chat': 'MESSAGE',

    // Speed test
    'speed_test': 'Speed test',
    'speed_running': 'Measuring real encrypted speed…',
    'speed_note': '1 GB would take about {gb}',
    'speed_declined': 'Refused — the other device must trust you and allow speed tests.',

    // Folder sync
    'sync_title': 'Sync folders',
    'sync_manage': 'Manage sync folders ({n})',
    'sync_explain':
        'Two-way: new and newer files go both ways. Older copies go to ".sudosend-archive"; deletions are not synced.',
    'sync_new': 'Sync a folder',
    'sync_none': 'No synced folders yet.',
    'sync_need_device': 'Bring a trusted device online to set up a sync.',
    'sync_trusted_only': 'Folder sync works between trusted devices only.',
    'sync_declined': '{name} declined the sync.',
    'sync_invite_notif': 'wants to sync the folder "{name}"',
    'sync_invite_body':
        'Wants to keep the folder "{name}" in sync with you. Pick a folder on this device; new and newer files will flow both ways. This device will be trusted.',
    'sync_choose_folder': 'Choose folder',
    'sync_status': 'Last sync: {time} · {n} files sent',
    'sync_never': 'never',
    'sync_now': 'Sync now',
    'sync_running': 'Syncing…',
    'sync_remove': 'Stop syncing',
    'sync_unsupported': 'Not available on iOS yet.',
    'sync_off': 'Folder sync is switched off in Features.',
    'incoming_sync': 'FOLDER SYNC',

    // Compression
    'compressed_saved': 'Compression saved {size}',
  },
  'ar': {
    'tab_messages': 'الرسايل',
    'close': 'اقفل',
    'got_it': 'تمام',
    'more_info': 'دي إيه؟',
    'online': 'متصل',
    'device_actions': 'المزيد',
    'act_message': 'ابعت رسالة',

    's_features': 'المزايا',
    's_features_sub': 'شغّل أو اقفل أي ميزة إضافية · دوس (i) تعرف بتعمل إيه',
    'cat_device_sub': 'الاسم، البصمة، والمفتاح محفوظ فين',
    'cat_receiving_sub': 'فولدر الحفظ، القبول التلقائي، الإشعارات، حد السرعة',
    'cat_privacy_sub': 'وضع التخفي، الأجهزة الموثوقة والمحظورة، سجل المراجعة',
    'cat_usage_sub': 'بعت واستلمت قد إيه، لكل جهاز',
    'cat_appearance_sub': 'اللغة والمؤثرات',
    'cat_about_sub': 'الإصدار، البروتوكول، الكود، الترخيص',
    'fg_transfer': 'النقل',
    'fg_devices': 'بين أجهزتك',
    'fg_noapp': 'أجهزة من غير التطبيق',

    'f_compression': 'ضغط ذكي',
    'f_compression_sub': 'بيضغط النصوص والأكواد واللوجات والمستندات وهي بتتبعت.',
    'f_previews_send': 'ابعت معاينة للصور',
    'f_previews_send_sub': 'صور مصغّرة مع الطلب عشان الطرف التاني يشوف إيه جاي.',
    'f_previews_show': 'اعرض معاينة الصور',
    'f_previews_show_sub': 'اعرض الصور المصغّرة اللي الأجهزة التانية بتبعتها قبل ما تقبل.',
    'f_queue': 'ابعت أول ما يفتح',
    'f_queue_sub': 'حط ملفات في الطابور لجهاز موثوق مقفول دلوقتي.',
    'f_chat': 'الرسايل',
    'f_chat_sub': 'رسايل سريعة مشفّرة مع الأجهزة الموثوقة، محفوظة كمحادثات.',
    'f_sync': 'مزامنة فولدر',
    'f_sync_sub': 'خلي فولدر نسخة طبق الأصل على جهازين موثوقين، في الاتجاهين.',
    'f_speed': 'اسمح باختبار السرعة',
    'f_speed_sub': 'الأجهزة الموثوقة تقدر تقيس السرعة الحقيقية للجهاز ده.',
    'f_web': 'المشاركة بالمتصفح',
    'f_web_sub': 'ابعت واستقبل من أي جهاز فيه متصفح.',

    'i_compression':
        'قبل ما كل حتة (256 كيلو) تتشفّر، SUDOSEND بيحاول يضغطها. لو صغرت 10% أو أكتر بتتبعت مضغوطة، غير كده بتتبعت زي ما هي. الملفات المضغوطة أصلاً (صور، فيديو، ZIP، APK، PDF، ملفات أوفيس) مش بيحاول فيها، ولو 3 حتت ورا بعض ما صغروش بيبطّل يحاول في الملف ده.\n\nالنتيجة: النصوص واللوجات والأكواد وCSV وقواعد البيانات والصور غير المضغوطة بتوصل أسرع بكتير على واي فاي ضعيف. فحص SHA-256 بيتعمل على البيانات الأصلية، فمفيش أي حاجة ممكن تضيع.\n\nلازم الجهازين يكونوا مشغّلينها. اقفلها لو الجهاز ده معالجه ضعيف جداً والشبكة سريعة جداً.',
    'i_previews_send':
        'لما تبعت صور، SUDOSEND بيعمل صورة مصغّرة صغيرة (أقصى 96 كيلو، لحد 8 صور) ويحطها مع الطلب، عشان المستلم يشوف الصور قبل ما يقبل.\n\nالمصغّرات بتمشي جوه نفس القناة المشفّرة. اقفلها لو مش عايز المحتوى يبان قبل ما الطرف التاني يقبل.',
    'i_previews_show':
        'بيعرض المصغّرات اللي المرسل حطها في نافذة الطلب، عشان تعرف إنت بتقبل إيه.\n\nالصور بيفكها مُفكّك الصور بتاع النظام. لو بتقبل من ناس تعرفهم بس سيبها شغالة. لو على شبكة مش موثوقة وعايز أقل سطح هجوم ممكن، اقفلها.',
    'i_queue':
        'بيعرض أجهزتك الموثوقة المقفولة تحت قايمة الأجهزة. دوس على واحد تحط اللي مختاره في الطابور، وبيتبعت لوحده (مع إعادة محاولة) أول ما الجهاز ده يظهر على الشبكة.\n\nلو قفلتها الاختيار بيختفي، واللي في الطابور بيتبعت عادي.',
    'i_chat':
        'بيضيف تبويب الرسايل. ابعت نصوص قصيرة للأجهزة الموثوقة — لينكات، أكواد، ملاحظات — بنفس التشفير من الطرف للطرف زي الملفات. الرسايل من الأجهزة الموثوقة بتوصل من غير سؤال، ومن غيرها بيتسألك الأول.\n\nالمحادثات محفوظة على الجهاز ده بس (في فولدر التطبيق)، لحد 500 رسالة لكل جهاز. تقدر تمسح أي محادثة في أي وقت. لو قفلتها التبويب بيختفي والنصوص بتوصل كنقل نص عادي.',
    'i_sync':
        'بيخلي فولدر نفس الشكل على جهازين موثوقين. كل دقيقة (وأول ما الجهاز التاني يفتح) كل طرف بيطلب من التاني قايمة ملفاته ويبعتله الملفات الجديدة أو الأحدث. الاتنين بيعملوا كده فبتبقى مزامنة في الاتجاهين.\n\nقواعد الأمان:\n• بين الأجهزة الموثوقة بس.\n• آخر تعديل هو اللي بيكسب؛ النسخة القديمة بتتنقل لـ ".sudosend-archive" جوه الفولدر — عمرها ما بتتمسح.\n• مسح ملف مش بيتزامن، فغلطة على جهاز عمرها ما تمسح التاني.\n• الملفات والفولدرات المخفية (اللي بتبدأ بـ ".") بتتساب.\n\nابدأها من قايمة "المزيد" بتاعة أي جهاز أو من "إدارة فولدرات المزامنة". مش متاحة على iOS.',
    'i_speed':
        'اختبار السرعة بيبعت بيانات عشوائية لمدة 6 ثواني جوه القناة المشفّرة الحقيقية ويقولك إيه اللي وصل فعلاً — يعني السرعة اللي نقلك هياخدها بجد، مش رقم سرعة الواي فاي النظري.\n\nلو شغالة، الأجهزة الموثوقة تقدر تعمل اختبار على الجهاز ده، ومش بيكتب أي حاجة على التخزين. الأجهزة غير الموثوقة بتترفض دايماً. تقدر تعمل اختبار بنفسك من قايمة "المزيد" لأي جهاز موثوق.',
    'i_web':
        'أي موبايل أو لابتوب أو تلفزيون فيه متصفح يقدر ينزّل منك أو يرفعلك — من غير تطبيق. بتاخد لينك خاص (وQR) فيه توكن عشوائي، وPIN اختياري، ومدة انتهاء، وحد أقصى للتحميلات.\n\nالنقل ده HTTP عادي على شبكتك المحلية (المتصفحات مش بتتكلم بروتوكول Wraith)، فاستخدم الـ PIN على الواي فاي المشترك. لو قفلتها الزراير بتختفي وأي مشاركة شغالة بتقف.',
    'i_sender_folders': 'بيحط ملفات كل جهاز في فولدر لوحده، مثلاً "SUDOSEND/Seif-Laptop/". مفيد لو كذا جهاز بيبعتولك.',
    'i_auto_accept':
        'الملفات من الأجهزة اللي عاملها موثوقة بتتقبل من غير ما تسأل. الأجهزة الغريبة بيتسألك عنها دايماً مع كود الـ 6 أرقام للمقارنة.\n\nسيبها مقفولة لو ناس تانية ساعات بتستخدم أجهزتك الموثوقة.',
    'i_auto_copy': 'لما حد يبعتلك نص، بيتنسخ على الحافظة على طول عشان تلصقه.',
    'i_background': 'بيسيب إشعار صغير عشان أندرويد ما يقفلش SUDOSEND، فتقدر تستقبل والتطبيق مقفول. بيصرف بطارية شوية زيادة.',
    'i_notifications': 'إشعار للطلبات الجاية (بزرار قبول/رفض على أندرويد)، والنقل اللي خلص، والرسايل الجديدة.',
    'i_speed_limit':
        'بيحدد أقصى سرعة الجهاز ده بيبعت بيها. كل حاجة لوكال — الموضوع مش باقة نت. الموضوع وقت الواي فاي: نقل كبير ممكن يخلي مكالمات الفيديو والألعاب تهنّج لكل اللي على نفس الراوتر. حط حد عشان تبقى ذوق، و"من غير حد" هو الأسرع.',
    'i_hot':
        'بيعمل "SUDOSEND Outbox" في الفولدر الرئيسي، فيه فولدر لكل جهاز موثوق. أي حاجة ترميها فيه بتتبعت للجهاز ده لوحدها أول ما يفتح وبعدين تتنقل لـ "Sent". حلو للسكريبتات والسحب والإفلات السريع.',
    'i_clip_sync':
        'انسخ على جهاز والصق على التاني. الحافظة بتتبعت للأجهزة الموثوقة بس ومشفّرة. على الموبايلات النظام بيسمح بقراية الحافظة بس والتطبيق مفتوح.\n\nخلي بالك: الباسوردات اللي بتنسخها بتتزامن هي كمان.',
    'i_ring': 'أجهزتك الموثوقة تقدر تخلي الجهاز ده يرنّ بصوت عالي — حتى لو صامت — عشان تلاقيه. الأجهزة الموثوقة بس.',
    'i_stealth':
        'الجهاز ده بيبطّل يعلن عن نفسه. محدش هيشوفه في القايمة، بس لسه بيرد على الأجهزة اللي واثق فيها، وتقدر تبعت منه عادي. مفيد على الواي فاي العام.',
    'i_trusted':
        'الأجهزة اللي وثقت فيها (بعد ما قارنت كود الـ 6 أرقام أو مسحت QR). مفتاح هويتها متثبّت: لو حد انتحل شخصيتها النقل بيتمنع. الغي الثقة لو جهاز ضاع منك.',
    'i_blocked': 'الأجهزة اللي حظرتها. طلباتها بتترفض في صمت من غير ما يظهرلك حاجة.',
    'i_audit': 'سجل بكل نقل خلص (الأسماء، الأحجام، الأجهزة، الأوقات — من غير محتوى الرسايل أبداً). صدّره JSON للأرشيف أو المراجعة.',
    'i_rejected':
        'الاتصالات اللي اترفضت من حماية الإغراق أو قايمة الحظر من ساعة ما التطبيق اشتغل. رقم كبير على شبكة البيت ممكن يعني إن في حاجة بتفحص جهازك.',
    'i_effects':
        'كامل: بلور زجاج حي وخلفية متحركة (محتاج كارت شاشة كويس). متوازن: نفس الشكل من غير بلور حي — ناعم على أغلب الأجهزة. خفيف: من غير ظلال ولا أنيميشن، الأحسن للراسبري باي والموبايلات القديمة والتلفزيونات.',
    'i_key_storage':
        'مكان حفظ مفتاح الهوية الخاص بالجهاز ده. Android Keystore وWindows DPAPI بيشفّروه بمفتاح النظام بيحميه، فلو نسخت فولدر التطبيق لجهاز تاني هويتك مش بتتنسخ.',

    'chat_empty': 'مفيش رسايل لسه',
    'chat_empty_sub': 'وثّق جهاز (قارن الكود أو امسح الـ QR بتاعه) عشان تبدأ تراسله.',
    'chat_new': 'ابدأ محادثة',
    'chat_start': 'دوس عشان تبعت رسالة',
    'chat_hint': 'رسالة',
    'chat_offline': 'مش متصل',
    'chat_from': 'رسالة من {name}',
    'chat_retry': 'دوس تعيد',
    'chat_clear': 'امسح المحادثة',
    'chat_clear_confirm': 'تمسح كل الرسايل مع الجهاز ده من على الجهاز ده؟',
    'incoming_chat': 'رسالة',

    'speed_test': 'اختبار السرعة',
    'speed_running': 'بنقيس السرعة الحقيقية المشفّرة…',
    'speed_note': '1 جيجا هياخد حوالي {gb}',
    'speed_declined': 'اترفض — الجهاز التاني لازم يكون واثق فيك ومشغّل اختبار السرعة.',

    'sync_title': 'فولدرات المزامنة',
    'sync_manage': 'إدارة فولدرات المزامنة ({n})',
    'sync_explain': 'في الاتجاهين: الملفات الجديدة والأحدث بتروح وتيجي. النسخ القديمة بتروح ".sudosend-archive"، والمسح مش بيتزامن.',
    'sync_new': 'زامن فولدر',
    'sync_none': 'مفيش فولدرات متزامنة لسه.',
    'sync_need_device': 'افتح جهاز موثوق على الشبكة عشان تعمل مزامنة.',
    'sync_trusted_only': 'مزامنة الفولدرات بين الأجهزة الموثوقة بس.',
    'sync_declined': '{name} رفض المزامنة.',
    'sync_invite_notif': 'عايز يزامن الفولدر "{name}"',
    'sync_invite_body':
        'عايز يخلي الفولدر "{name}" متزامن معاك. اختار فولدر على الجهاز ده؛ الملفات الجديدة والأحدث هتروح وتيجي في الاتجاهين. الجهاز ده هيبقى موثوق.',
    'sync_choose_folder': 'اختار فولدر',
    'sync_status': 'آخر مزامنة: {time} · اتبعت {n} ملف',
    'sync_never': 'ولا مرة',
    'sync_now': 'زامن دلوقتي',
    'sync_running': 'بيزامن…',
    'sync_remove': 'وقّف المزامنة',
    'sync_unsupported': 'مش متاحة على iOS لسه.',
    'sync_off': 'مزامنة الفولدرات مقفولة من المزايا.',
    'incoming_sync': 'مزامنة فولدر',

    'compressed_saved': 'الضغط وفّر {size}',
  },
};
