--[[
    Extensive Health Rework B42
    The Last Prescription radio message builders.
]]--

local EHR_RadioMessages = {}

local Colors = {
    HOST = { r = 0.95, g = 0.85, b = 0.72 },
    TIP = { r = 0.50, g = 0.90, b = 0.62 },
    WARNING = { r = 1.00, g = 0.35, b = 0.25 },
    MEDICAL = { r = 0.45, g = 0.78, b = 1.00 },
    STATIC = { r = 0.65, g = 0.65, b = 0.65 },
}

local morningTips = {
   --1
    {
        "Hey hey. It's yours truly, Amelie. How's your morning, folks? Mine is awful... as usual.",
        "I hate waking up early... but here I am, doing it for you. Try to appreciate that before something eats me.",
        "Anyway... if your hands are covered in blood, maybe don't eat with them. Revolutionary advice, I know.",
        "Soap, clean water, a clean cloth. Use what you have, but clean your hands before touching food.",
        "Unless you enjoy sprinting across town while your guts perform a marching band routine. Best-case scenario, by the way.",
        "Yours truly, Amelie. See ya later.",
    },
--2
    {
         "Mmhh.. aaaaggghhmmmm.. Hello folks... Amelie here. Hope your sleep was awful as mine ",
        "A tip for today. Wound that gets hotter, darker, or meaner by the hour is not being dramatic. It may be infected.",
        "Change dirty bandages early. Desifect every wound even if it looks like a small scratch.",
        "If it starts swelling, leaking, or throbbing like it has opinions, clean it before it wins the argument.",
        "Boiled water, disinfectant, alcohol wipes, whatever you have. Luxury medicine died with the power grid.",
        "Do not keep poking it with dirty fingers to check if it's still bad. Congratulations, now it's worse.",
        "Yours truly, Amelie. Try not to rot from a scratch. It would be embarrassing.",
    },
--3
    {
        "Heeelloooouu! And a special greeting to whoever woke up half of March Ridge with a shotgun.",
        "He or she is probably dead by now. Yeah... most likely. Definitely. Anyway, advice for the rest of you.",
        "Corpse smell is not bravery training. Leave immediately.",
        "Fresh air is treatment. A proper mask is prevention.",
        "If you start feeling sick near a pile of bodies, do not stand there investigating like a curious raccoon.",
        "Move, breathe, cover your face. Congratulations, you have discovered the ancient art of not poisoning yourself.",
    },
--4
    {
        "*noises*, *noises*... God damn, this thing is harder than using an ESU. Hello, by the way.",
        "Raw wild game is a parasite lottery. Cook it through, especially rat, boar, bear, fox, and anything you found already dead.",
        "If the center is still cold or pink, congratulations, it is not dinner yet.",
        "Yes, I know you're hungry. The worms in your stomach will be thrilled to hear your excuse.",
        "Boil it, roast it, burn it a little if you have to. Charcoal seasoning beats intestinal misery.",
        "Yours truly, Amelie. Try not to lose a fight against breakfast.",
    },
--5
    {
        "Welcome to The Last Prescription! You know what I miss the most? Beaches... calm, breezy, and full of people who are probably dead now.",
        "But you know what I hate the most? A fucking heat! I hate it, hate it hate it ha..*noises*",
        "Heat is more dangerous that you might think. It kills quietly. Shade, water, and rest are medical supplies when the temperature starts climbing.",
        "A hat buys time. It does not make you immortal. Stunning concept, I know.",
        "If you stop sweating, get dizzy, or feel your head cooking from the inside, move before you become sidewalk decor.",
        "Drink water before you feel desperate. Desperation is not a hydration strategy, despite what idiots keep proving.",
        "Yours truly, Amelie. Stay cool, stay shaded, and try not burn to crisps.",
    },
--6
    {
        "*Gulp* *gulp*... aaah. Hello, my lovelies. What have you been doing? Staying healthy like my grandpa in his nineties?",
        "Anyway, here's some advice. I know you love advice. Sometimes I wonder how some of you survived this long.",
        "Untreated water can look clean and still ruin you. Boil it when you can.",
        "If your gut turns violent after bad water, hydration becomes the treatment, not a luxury.",
        "Sip slowly, keep drinking, and do not trust a puddle just because it looks polite.",
        "Yours truly, Amelie Crowe. Remember: clear water can still betray you. Very relatable, honestly.",

    },
--7
    {
        "A deep wound with glass inside is not just a cut. Remove the fragments, disinfect it, and keep watching it.",
        "If something is still buried in there, do not pretend your body will simply negotiate with it.",
        "Use clean tools, clean hands, and whatever disinfectant you can still find. Yes, clean. That word again.",
        "If the wound gets stiff, swollen, hot, or starts hurting more, congratulations, the problem has evolved.",
        "Have you ever heard of Tetanus? It's kinda rare until it is yours.",
        "Yours truly, Amelie. Try not to lose to a shinny glass or a nail, would ya?.",
    },
--8
    {
        "What's up, survivors? Did you stock enough meds? If your answer is yes, you're wrong. It is never enough.",
        "Here's a little advice for those of you who like shiny, colorful pills a bit too much.",
        "Do not stack serious medication just because you're scared. A bigger dose is not a bigger cure.",
        "Follow the interval. Your liver and kidneys are already negotiating with the apocalypse.",
        "If the label says wait, then wait. I know, reading is hard. Dying from impatience is harder.",
        "Yours truly, Amelie. Take the medicine, not the whole damn pharmacy.",
    },
--9
    {
        "Good morning, survivors. Quick question: how much blood do you think you need to keep functioning? Hint: more than 'whatever is currently leaking out.'",
  "Blood is not decoration. It carries oxygen, heat, and everything your body needs to keep pretending it has a plan.",
  "Lose too much of it, and simple tasks become ambitious. Walking, thinking, standing... all very fancy hobbies now.",
  "If you're bleeding, stop the bleeding first. Bandage it, press it, and do not admire the color like an idiot.",
  "Dizziness, weakness, cold skin, and a racing heart are your body politely screaming that the tank is running low.",
  "Yours truly, Amelie. Keep your blood inside you. Revolutionary, I know.",
    },
--10
    {
 "Hi, It's me again. Still not dead. Today's topic is corpses, mold, and your lungs. Charming, I know. Try not to swoon.",
  "Cadaveric Aspergillosis does not care how tough you think you are. Breathing rot is still breathing rot.",
  "Old bodies, damp air, and closed spaces make a lovely little nursery for things you do not want inside your chest.",
  "If you start coughing, wheezing, or feeling weak after digging through corpse piles, maybe stop treating dead people like furniture.",
  "Fresh air, distance, and a proper mask are not optional luxuries. They are the difference between clever and stupid with symptoms.",
  "Yours truly, Amelie. If the dead are growing things, do not inhale the harvest."
    },
--11
    {
         "Hello, lads. Amelie on touch. Today's miracle of modern misery: the common cold. Yes, even the apocalypse kept the boring diseases.",
  "A runny nose and sore throat may not sound dramatic, but coughing through a stealth run is a beautiful way to become lunch.",
  "Rest when you can, stay warm, and drink clean water. Basic advice, somehow still too advanced for half of you.",
  "If you're sneezing into your hands, congratulations, you have invented portable contamination.",
  "Cover your mouth, wash your hands, and stop sharing bottles like civilization is still handing out second chances.",
  "Yours truly, Amelie. A cold probably won't kill you, but your stupid decisions might.",
    },
--12
    {
        "Mhmhmm.. Is it already 9??! Still better than waking up in my office after surgery...",
        " Today we discuss what happens when your skull loses an argument to a big bonk, fall or a car crash",
  "A concussion is not just 'getting your bell rung.' Your brain is soft, expensive, and currently living in a bone helmet with terrible suspension.",
  "If you feel dizzy, confused, nauseous, sleepy, or your vision starts doing creative little tricks, stop acting heroic and sit down.",
  "Do not sprint back into danger because you 'feel mostly fine.' Mostly fine is how idiots upgrade minor injuries into permanent problems.",
  "Rest, avoid bright lights when you can, and keep someone nearby if things get worse. Yes, supervision. Like a child, but louder.",
  "Yours truly, Amelie. Protect your head. You only get one brain, and frankly, some of you are already using it very lightly.", 
    },
--13    
    {
         "Hello everyone, and hello to the walking dead folks who might overhear. Today we talk about hyperkeratotic scabies. Yes, even your skin can decide to become a cursed little ecosystem.",
  "Thick, crusted, itching skin is not just bad luck or poor fashion. It can mean mites are throwing a family reunion on you.",
  "Do not scratch until you bleed and then act surprised when everything gets worse. That is not treatment, that is teamwork with the enemy.",
  "Wash clothes, bedding, and anything your skin keeps touching. If you ignore the fabric, congratulations, you made the problem portable.",
  "Topical treatment helps, but consistency matters. One lazy application and the little bastards may file a renewal request.",
  "Yours truly, Amelie. If your skin starts hosting tenants, evict them properly.",
    },
--14    
    {
        "The one and only Last Prescription live again. Today we talk about hypothermia, also known as your body slowly losing a debate with the weather.",
  "Cold is not just uncomfortable. It steals your strength, slows your hands, fogs your head, and makes every mistake more expensive.",
  "Wet clothes make it worse. Wind makes it worse. Standing around pretending you're fine makes it worse, obviously.",
  "Get dry, get covered, get indoors, or get near a fire before your body starts shutting down the less important departments. Like judgment.",
  "Shivering is a warning, not background noise. If it stops while you're still freezing, that is not improvement. That is bad news wearing a hat.",
  "Yours truly, Amelie. Stay warm, stay dry, and do not let the weather kill you with paperwork-level boredom.",
    },
--15
    {
         "Yours truly Amelie back online!. Today we discuss the Knox Infection",
  "If our undead neighbors bites you than it's probably it. THE END. Not right away tho, no, no, no",
  "Fever, panic, sickness, and that lovely sense of doom. I don't believe in god but pray before examining the wound.",
  "Clean the wound anyway, bandage it anyway, keep moving anyway. Giving up early is still pathetic, even when the odds are insulting.",
  "And if you know you are turning, do the polite thing: step away from the group before you become everyone's problem with teeth.",
  "Yours Amelie Crowe. If Knox gets you, try to be useful before you become educational. For the rest of us..",
    },
--16    
    {
         "Another great day.. right? Amelie here. With your favourite advices.Today we talk about pneumonia",
  "A cough, fever, chest pain, and weakness are not just your body being dramatic. Your lungs may be filing a formal complaint.",
  "Cold, exhaustion, wet clothes, and sleeping like a raccoon in a ditch can all help turn a bad cough into something uglier.",
  "Rest when you can, stay warm, drink clean water, take antibiotics and stop pretending you can outrun sickness with heroic stupidity.",
  "If every breath feels harder than it should, take it seriously. Air is one of those little luxuries people only respect when it stops cooperating.",
  "Yours truly, Amelie. Keep your lungs working. They are annoyingly important.",
    },
--17
    {
          "Heloooo still living! Yours truly still here, well and breathing. Today we talk about sepsis",
  "A dirty wound is bad. A dirty wound with fever, chills, confusion, weakness, or a racing heart is even worse.",
  "Sepsis does not politely wait for you to finish looting the pharmacy. It moves fast, because apparently even infections have better time management than you.",
  "Clean wounds early, change filthy bandages, and treat infections before they start making executive decisions for your entire bloodstream.",
  "If you feel suddenly worse after an infected cut, bite, or burn, stop pretending it is fine. Fine does not usually come with shaking and seeing stars.",
  "Yours truly, Amelie. Respect small infections before they promote themselves.",
    },
--18
    {
        "What's up? You know I would gave everything for a granola bar right now. Anyway today we talk about trichinosis",
  "Wild game can carry parasites, especially pork, bear, boar, and whatever mystery meat you dragged out of the woods like a proud little goblin.",
  "If the center is still pink, cold, or suspiciously chewy, it is not rustic cuisine. It is a medical subplot waiting to happen.",
  "Cook it through. Not wave it near a fire. Actually cook it. Or you'll get unfriendly snakes neighbors inside you. Hate snakes by the way",
  "Stomach pain, diarrhea, fever, weakness, and aching muscles after bad meat are not proof you are tough. They are proof dinner fought back.",
  "Yours truly, Amelie. Eat cooked food, not consequences.",
    },
--19
    {
         "Hello world! Or what's left of it. Amelie again with some advices for ya. Today we talk about body temperature",
  "Too hot, too cold, too shaky, too sweaty... your body is not being poetic. It is warning you before the machinery starts failing.",
  "Fever can mean infection. Chills can mean trouble. Ignoring both because you are 'probably fine' is how the probably part disappears.",
  "Check yourself after wounds, bad food, dirty water, cold nights, and corpse-stinking rooms. Patterns matter, even if thinking hurts.",
  "Rest, hydrate, warm up, cool down, and treat the cause instead of just complaining at your own skin like it owes you money.",
  "Yours truly, Amelie. Respect the temperature, or enjoy being cooked, frozen, or medically interesting.",
    },
--20
    {
          "Hello, survivors. Today we talk about stress, because apparently being hunted by the dead is bad for the nerves. Shocking, I know.",
  "Stress is not just whining with extra steps. It makes your hands worse, your sleep worse, your focus worse, and your decisions impressively stupid.",
  "Too much panic can turn a simple problem into a full circus act, starring you, a locked door, and ten dead neighbors.",
  "Breathe, rest, read something boring, smoke if you must, and stop sprinting through every problem like fear is a navigation system.",
  "If your mind keeps screaming, lower the noise around you. Darkness, hunger, pain, and exhaustion are all very talented little stress chefs.",
  "Yours truly, Amelie. Keep your head steady, or the apocalypse will use it as a chew toy.",
    },
--22
    {
        "Amelie Crowe and Last Prescription online!. Today we talk about literature, because apparently paper can still do something useful besides starting fires.",
  "Specialized medical books can teach you about diseases, symptoms, and treatments. Even during apocalypse you still need to learn. First aid especially",
  "If you find one, read it before using it as kindling. Your future self may appreciate knowing the difference between a cold and your lungs declaring independence.",
  "The more you understand, the faster you can spot trouble. Fever, rash, cough, infection... all less mysterious when you have opened a book once in your life.",
  "No, reading does not make you genius surgeon like me. But it does make you slightly less dangerous to yourself, which is honestly progress.",
  "Yours truly, Amelie. Read the manual before your body becomes the tutorial.",
    },
  
}

local afternoonTalk = {
--1    
    {
       "Good afternoon, survivors. This is Amelie Crowe, broadcasting at three sharp, because apparently punctuality survived the end of the world.",
    "If you are hearing this, congratulations. Your radio works, your ears work, and statistically speaking, that already puts you above average.",
    "I used to run a clinic before everything went beautifully, professionally insane.",
    "Now I run this little miracle of static, sarcasm, and medical disappointment.",
    "Every day, same hour. I talk, you listen, and maybe fewer of you die from stupid little things.",
    "Do not get sentimental. I am doing public service, not adopting strays.",
    },
--2
    {
         "Good afternoon. Amelie Crowe here, still alive, still annoyed, still better prepared than most of you.",
    "I found a clinic supply closet this morning. Mostly empty, of course. Humanity fell, but apparently someone still had time to steal all the antibiotics.",
    "There were three boxes of gloves, half a bottle of disinfectant, and a motivational poster about teamwork.",
    "I took the gloves and left the poster. Even I have standards.",
    "Today's lesson: if you find medical supplies, sort them immediately. Panic hoarding is not inventory management.",
    "Write labels. Count doses. Keep the good stuff dry. There, I have improved your life. Try not to ruin it.",
    },
--3
    {
         "Good afternoon, my beautifully doomed listeners. This is The Last Prescription, and I am still your least comforting voice.",
    "Someone passed near the station last night. I heard a car engine, then shouting, then nothing smart after that.",
    "If that was you, well... your driving had personality. Mostly the kind that gets people killed.",
    "I stayed inside, because I possess the rare survival trait called not running toward noise.",
    "There are fresh dead around the south fence now. Not many. Enough to be rude.",
    "I will clear them later. Or I will pretend I did and call it strategic containment.",
    },
--4
    {
        "Good afternoon. Amelie here. The generator coughed twice before starting today, which is always charming.",
    "Machines have personalities after the world ends. This one is old, dramatic, and deeply committed to testing my patience.",
    "I patched a fuel line with tape, prayer, and professional resentment.",
    "If your equipment starts making new sounds, do not ignore it. New sounds are machines writing goodbye letters.",
    "Check your fuel, your oil, your wiring, and your exits before you settle anywhere.",
    "A shelter is only safe until one small part decides to become a problem.",
    },
--5
    {
        "Good afternoon, survivors. Today I discovered that the roof leaks directly above my medical shelf.",
    "Fantastic design. Really inspired. Ten out of ten, would curse at architecture again.",
    "I saved most of the supplies. Lost some bandages, a few notes, and one very smug-looking box of painkillers.",
    "Water damage ruins medicine faster than zombies ruin neighborhood property value.",
    "Keep supplies off the floor, away from windows, and out of damp rooms.",
    "Yes, this sounds obvious. So does 'do not drink bleach', and yet here we are as a species.",
    },
--6
    {
          "Good afternoon. This is Amelie Crowe, broadcasting from a room that smells like dust, fuel, and poor decisions.",
    "I found old patient files today. Names, dates, allergies, little notes from before everything became a meat grinder.",
    "Mrs. Vance hated penicillin. Mr. Ellroy lied about smoking. A kid named Jamie kept hiding stickers in the exam room.",
    "Funny how paper can make ghosts without needing a single corpse in the room.",
    "Keep records if you are traveling with others. Blood type, allergies, conditions, medications.",
    "Memory fails under stress. Paper, annoyingly, tends to be smarter.",
    },
--7
    {
         "Good afternoon. One week of broadcasts. Look at us, building routine in the ruins. Disgusting. Almost hopeful.",
    "A man knocked on the outer door this morning. Said he needed help. Said his friend was sick.",
    "I asked how sick. He said bitten. Then he asked if I had a cure.",
    "I told him I had bad news, clean bandages, and no patience for fairy tales.",
    "He cried. I did not open the door.",
    "Call me cruel if you want. Cruel is still breathing.",
    },
--8
    {
 "Good afternoon, listeners. The man from yesterday left before sunrise.",
    "He also left a backpack at the fence. Inside: canned beans, a cracked watch, and a note that said 'sorry'.",
    "For what, exactly? Existing? Asking? Surviving badly? People apologize for strange things at the end.",
    "I took the beans. I kept the note. Do not make that face, you would have taken the beans too.",
    "If you cannot help someone, at least be honest. False hope is just poison with softer packaging.",
    "And yes, I hate that sentence too.",
    },
--9
    {
         "Good afternoon. Amelie here. Today's weather: grey, wet, and emotionally committed to making everything worse.",
    "The dead are gathering near the east road. Not a horde yet. More like a committee of unpleasant intentions.",
    "I watched them for twenty minutes. No pattern, no purpose, just hunger wearing old clothes.",
    "People used to ask me why I sounded cynical. Adorable question, really.",
    "If a route starts filling with dead, change the route before pride turns into a funeral.",
    "The map is not sacred. Your plan is not sacred. Staying alive is the only thing with seniority.",
    },
--10
    {
        "Good afternoon, survivors. I had a visitor on the frequency today.",
    "Not a person, exactly. A burst of music, two words, then static. Could have been another station. Could have been ghosts with poor timing.",
    "The words were 'Crowe, answer.' That is my name, unfortunately, so now the day is interesting in the worst way.",
    "I tried replying. Nothing came back.",
    "If you hear voices on the radio, do not chase them blindly. Hope makes terrible navigation.",
    "But yes, before you ask, I will be listening again tonight. I am arrogant, not immune to curiosity.",
    },
--11
    {
 "Good afternoon. Amelie Crowe, still here, still pretending this microphone is a social life.",
    "The voice returned last night. Male, tired, probably local. He knew my old clinic call sign.",
    "That means he is either someone from before, or someone reading things he should not have found.",
    "He said the hospital still has power in one wing. Then the signal died, because drama apparently survived too.",
    "A powered hospital is either a miracle or a beautifully lit death trap.",
    "I am not going today. See? Growth. Wisdom. Mild cowardice wearing a lab coat."
    },
--12
    {
         "Good afternoon. I said I was not going to the hospital. I lied. Character flaw. Very human of me.",
    "I only scouted the outer road. From a distance. With binoculars. Like a professional coward, which is the correct kind.",
    "There are lights in the upper windows. Real lights. Not reflections. Not lightning.",
    "There are also too many dead at the entrance, because of course paradise has a reception desk.",
    "Someone is in there, or something left the lights on.",
    "Either way, I came back before curiosity got expensive."
    },
--13
    {
  "Good afternoon. Today I reinforced the station door, because optimism is for people with backup generators.",
    "I moved the medicine cabinet, packed a field bag, and cleaned my old revolver.",
    "Relax. I am a doctor, not a hero. The revolver is for doors, locks, and extremely final conversations.",
    "The hospital signal returned at noon. Same voice. He said, 'We have vaccines.'",
    "That is either the best news in Kentucky or the laziest bait I have ever heard.",
    "And yes, I am insulted that it might still work."
    },
--14
    {
 "Good afternoon, survivors. Two weeks. If you made it this far, you are either careful, lucky, or hiding in a bathroom with crackers.",
    "The hospital voice has a name now. Daniel Price. Former emergency technician. Annoyingly convincing.",
    "He described the third-floor surgery wing, the staff lounge, the broken elevator, even the vending machine that stole my quarters in May.",
    "So either Daniel is real, or the universe has developed a very specific sense of humor.",
    "He says there are four people with him. One feverish. One injured. One child.",
    "That last detail was rude. Emotional blackmail with training wheels."
    },
--15
    {
   "Good afternoon. I did not sleep much. The walls made noises. The roof made noises. My brain joined in because it hates teamwork but loves sabotage.",
    "I keep thinking about the kid at the hospital. Daniel said her name is Rose.",
    "Could be fake. Could be real. Could be a trap with pigtails and a cough.",
    "I hate this. I hate that I care. I hate that caring still works.",
    "Today's advice: protect your soft parts. Not just organs. The other ones.",
    "The world will use them as handles if you let it."
    },
--16
    {
   "Good afternoon. I went farther today. Not inside. Just close enough to see the ambulance bay.",
    "There are bodies piled near the doors. Old ones. New ones. Some wearing hospital gowns.",
    "No screaming. No gunshots. No visible movement in the lit windows.",
    "I found a white cloth tied to a parking sign. Fresh knot. Fresh fabric.",
    "Someone wanted to be seen.",
    "I hate when mysteries start making eye contact."
    },
--17
    {
 "Good afternoon, survivors. This may be shorter than usual. I am packing.",
    "Yes, yes, make your judgmental little faces at the radio. I can feel them through the static.",
    "I am not moving permanently. I am going in, checking the hospital wing, and coming back before evening.",
    "Medical bag, water, mask, gloves, crowbar, flashlight, spare batteries. See? Preparation. The opposite of whatever most of you call planning.",
    "If I do not broadcast tomorrow, assume I am delayed before assuming I am dead.",
    "And if I am dead, try not to act surprised. It is unbecoming."
    },
--18
    {
  "Good afternoon. I am back. Barely. Do not clap. It will annoy me.",
    "The hospital has power, yes. It also has locked doors, blood trails, and a stairwell full of dead staff.",
    "Daniel is real. Rose is real. The others were real too, until recently.",
    "There are no vaccines. Not for Knox. Not for miracles. Just medicine, lies, and people trying to make fear sound scientific.",
    "Daniel said he lied because nobody comes for ordinary sickness anymore.",
    "The worst part is that he was right."
    },
--19
    {
 "Good afternoon. Rose is at the station now. Eight years old, fever down, attitude improving, currently judging my soup.",
    "Daniel did not come back with us.",
    "He held the stairwell long enough for us to leave, which is a heroic way of saying he made a decision I did not get to argue with.",
    "I hate heroes. They make survivors feel untidy.",
    "Rose asked if I am always mean. I told her only when awake.",
    "She said that sounds exhausting. Smart kid. Terrible taste in soup."
    },
--20
    {
  "Good afternoon, survivors. Rose is sleeping. The station is quiet, which means my thoughts are being obnoxiously loud.",
    "The hospital followed us. Not literally, calm down. But some dead drifted this way after the noise.",
    "I cleared three near the fence this morning. There are more in the trees.",
    "The generator is running rough again. Fuel is low. Food is lower. My tolerance for cheerful thinking is underground.",
    "I may need to move the broadcast equipment, or abandon it entirely.",
    "Before anyone gets dramatic, no, I have not decided. I am simply surrounded by bad options wearing different hats."
    },
--22
    {
 "Good afternoon. This is Amelie Crowe, broadcasting from The Last Prescription, possibly for the last time from this location.",
    "The dead reached the outer fence before dawn. Not a horde. Just enough to make staying here stupid.",
    "Rose asked if the radio people will miss us. I told her radio people are imaginary.",
    "Then she said, 'But you talk like they matter.'",
    "Awful child. Observant. Deeply inconvenient.",
    "We leave tonight. If the station goes silent, remember something useful I said and pretend it was your idea."
    },
--23
    {
     "Good afternoon, survivors. If this recording plays, then I either made it out, failed spectacularly, or forgot to turn off the loop. All equally possible.",
    "This is Amelie Crowe of The Last Prescription. Surgeon, broadcaster, professional disappointment, and apparently babysitter.",
    "The station is empty now. Supplies are gone. Notes are hidden under the loose floorboard near the desk. You are welcome.",
    "If you find this place, do not stay long. The fence will not hold, the generator is a liar, and the woods have been getting louder.",
    "Rose says I should end with something hopeful. Fine. Here: knowledge lasts longer than luck.",
    "Yours truly, Amelie. Keep breathing, keep learning, and do not make me haunt you over something preventable."
    },

}

local diseaseEpisodes = {
    {
        id = "food_poisoning",
        name = "Food Poisoning",
        cause = "Rotten food is the usual culprit. Burned or stale food can still do damage.",
        symptoms = "Nausea, vomiting, thirst, hunger shifts, and endurance loss.",
        treatment = "Anti-nausea tablets and electrolytes help. Activated charcoal can shorten the course.",
    },
    {
        id = "gastroenteritis",
        name = "Gastroenteritis",
        cause = "Dirty or bloody hands before eating. That is enough.",
        symptoms = "Hard nausea, vomiting, dehydration, and a gut that will not negotiate.",
        treatment = "Anti-diarrheal medication and electrolytes are relief. Antivirals handle the illness itself.",
    },
    {
        id = "trichinosis",
        name = "Trichinosis",
        cause = "Raw or undercooked wild game. Rats, boar, bear, fox, and similar meat are the danger zone.",
        symptoms = "Muscle pain, fever, weakness, and in severe cases, lethal systemic damage.",
        treatment = "Antiparasitic pills are the course. Muscle relaxants only ease the pain.",
    },
    {
        id = "dysentery",
        name = "Dysentery",
        cause = "Contaminated water. Rivers, toilets, and unsafe containers are not medical fountains.",
        symptoms = "Severe dehydration, abdominal pain, vomiting, and blood loss in advanced stages.",
        treatment = "Oral hydration, IV fluids, and the right antibiotics. Anti-diarrheal medication buys control.",
    },
    {
        id = "toxin_poisoning",
        name = "Toxin Poisoning",
        cause = "Poisonous berries or mushrooms. One bad bite can turn the whole day hostile.",
        symptoms = "Nausea, blurred vision, weakness, feverish collapse, and dangerous health loss.",
        treatment = "Activated charcoal can suppress the worst of it if taken early.",
    },
    {
        id = "corpse_sickness",
        name = "Putrefaction Sickness",
        cause = "Standing too long near decomposing corpses, especially without fresh air.",
        symptoms = "Eye irritation, nausea, dizziness, and collapse at high exposure.",
        treatment = "Fresh air first. Respiratory support can help after serious exposure.",
    },
    {
        id = "cadaveric_aspergillosis",
        name = "Cadaveric Aspergillosis",
        cause = "Fungal spores from damp, cold corpse-filled spaces.",
        symptoms = "Coughing, respiratory fatigue, fever, and worsening lung stress.",
        treatment = "Antifungal medication, inhaler support, and getting away from the source.",
    },
    {
        id = "common_cold",
        name = "Common Cold",
        cause = "Cold wet exposure, or being soaked long enough for your body to lose the argument.",
        symptoms = "Sneezing, mild fever, fatigue, and respiratory irritation.",
        treatment = "Rest, warmth, fluids, and cold and flu tablets.",
    },
    {
        id = "pneumonia",
        name = "Pneumonia",
        cause = "Often follows a neglected respiratory infection.",
        symptoms = "High fever, severe cough, chest pain, endurance collapse, and health loss.",
        treatment = "Antibiotics, fever control, cough medication, and bronchodilator support.",
    },
    {
        id = "hypothermia",
        name = "Hypothermia",
        cause = "Core temperature falling too far after cold exposure.",
        symptoms = "Shivering, slowed movement, confusion, collapse, and lethal body cooling.",
        treatment = "Warm shelter, dry clothing, rest, and time away from the cold.",
    },
    {
        id = "heat_exhaustion",
        name = "Heat Exhaustion",
        cause = "Working or standing too long in dangerous heat before true heat stroke begins.",
        symptoms = "Weakness, overheating, thirst, dizziness, and rising heat exposure.",
        treatment = "Shade, water, rest, and cooling before it becomes heat stroke.",
    },
    {
        id = "heat_stroke",
        name = "Heat Stroke",
        cause = "Extreme heat exposure after the body fails to cool itself.",
        symptoms = "Dangerous fever, confusion, collapse, thirst, and health drain.",
        treatment = "Immediate cooling. Ice packs or a cold bath can save a life.",
    },
    {
        id = "wound_infection",
        name = "Wound Infection",
        cause = "Dirty wounds, neglected bandages, and poor wound care.",
        symptoms = "Local pain, fever in serious stages, and progression toward systemic infection.",
        treatment = "Antibiotic ointment early. Broad spectrum antibiotics if it progresses.",
    },
    {
        id = "sepsis",
        name = "Sepsis",
        cause = "An infection breaking containment and becoming a whole-body emergency.",
        symptoms = "Extreme weakness, fever, health drain, and rapid decline without treatment.",
        treatment = "Clinical antibiotics and aggressive supportive care. Do not wait.",
    },
    {
        id = "tetanus",
        name = "Tetanus",
        cause = "Deep contaminated wounds, especially with embedded debris.",
        symptoms = "Muscle spasms, neck stiffness, trouble eating, fever, and lethal collapse.",
        treatment = "Tetanus antitoxin or immunoglobulin. Muscle relaxants only make symptoms bearable.",
    },
    {
        id = "ahtr",
        name = "Acute Hemolytic Transfusion Reaction",
        cause = "Incompatible blood transfusion.",
        symptoms = "Lower back pain, nausea, high fever, endurance loss, and severe health drain.",
        treatment = "Stop the reaction with IV fluids and furosemide support.",
    },
    {
        id = "concussion",
        name = "Concussion",
        cause = "A serious head impact after a fall or crash.",
        symptoms = "Headache, blurred vision, dizziness, nausea, and temporary health loss.",
        treatment = "Rest and time. Do not pretend your skull has a spare.",
    },
    {
        id = "hyperkeratotic_scabies",
        name = "Hyperkeratotic Scabies",
        cause = "Infestation after prolonged contact with soil or contaminated ground.",
        symptoms = "Itching, scratches, fever, spreading skin trauma, and severe health loss.",
        treatment = "Antiparasitic pills and topical permethrin.",
    },
    {
        id = "delirium",
        name = "Delirium",
        cause = "Prolonged extreme stress breaking mental stability.",
        symptoms = "Auditory hallucinations, disorganized speech, strange impulses, and visual distortion.",
        treatment = "Antipsychotics and removing the stress source if you can.",
    },
    {
        id = "knox_infection",
        name = "Knox Infection",
        cause = "A bite or infected wound from the dead.",
        symptoms = "Fever, anxiety, nausea, and the final progression everyone fears.",
        treatment = "There is no routine cure. Experimental therapy is rare and uncertain.",
    },
}

local function pick(list, day, salt)
    if not list or #list == 0 then return nil end
    local dayIndex = math.max(0, (tonumber(day) or 1) - 1)
    local index = (dayIndex + (salt or 0)) % #list
    return list[index + 1]
end

local function pickSequential(list, day)
    if not list or #list == 0 then return nil end
    local dayIndex = math.max(0, (tonumber(day) or 1) - 1)
    local index = (dayIndex % #list) + 1
    return list[index]
end

local function line(text, color, fx)
    color = color or Colors.HOST
    return {
        text = text,
        r = color.r,
        g = color.g,
        b = color.b,
        fx = fx or "",
    }
end

local function appendLines(target, texts, color, fxText)
    if not target or not texts then return end

    for i = 1, #texts do
        local fx = ""
        if fxText and i == #texts then
            fx = fxText
        end
        target[#target + 1] = line(texts[i], color, fx)
    end
end

function EHR_RadioMessages.GetDiseaseForDay(day)
    return pick(diseaseEpisodes, day, 0)
end

function EHR_RadioMessages.BuildMorningTip(day)
    local tip = pick(morningTips, day, 1) or morningTips[1]
    local broadcast = {
        line("<bzzt> The Last Prescription, 147.0. Amelie Crowe speaking.", Colors.STATIC),
    }
    appendLines(broadcast, tip, Colors.TIP, "EHX+4")
    return broadcast
end

function EHR_RadioMessages.BuildAfternoonTalk(day)
    local talk = pickSequential(afternoonTalk, day) or afternoonTalk[1]
    local broadcast = {
        line("<fzzt> The Last Prescription, afternoon check-in.", Colors.STATIC),
    }
    appendLines(broadcast, talk, Colors.HOST)
    return broadcast
end

function EHR_RadioMessages.BuildEveningDisease(day)
    local episode = EHR_RadioMessages.GetDiseaseForDay(day)
    if not episode then return nil end

    local broadcast = {
        line("<bzzt> The Last Prescription evening pathology note.", Colors.STATIC),
    }

    if episode.lines then
        appendLines(broadcast, episode.lines, Colors.MEDICAL, "EHK=" .. episode.id)
    else
        broadcast[#broadcast + 1] = line("Tonight's file: " .. episode.name .. ".", Colors.MEDICAL)
        broadcast[#broadcast + 1] = line("Cause: " .. episode.cause, Colors.HOST)
        broadcast[#broadcast + 1] = line("Symptoms: " .. episode.symptoms, Colors.WARNING)
        broadcast[#broadcast + 1] = line("Treatment: " .. episode.treatment, Colors.TIP)
        broadcast[#broadcast + 1] = line("Write the name down if you have paper: " .. episode.name .. ".", Colors.MEDICAL, "EHK=" .. episode.id)
    end

    return broadcast
end

return EHR_RadioMessages
