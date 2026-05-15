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
    {
        "If your hands are bloody, do not eat with them. Infection starts with the little shortcuts.",
        "Soap, rainwater, a clean cloth. Use what you have, but clean your hands before food.",
    },
    {
        "A wound that gets hotter, deeper in color, or more painful is not just angry. It may be infected.",
        "Change dirty bandages early. Waiting saves cloth and spends blood.",
    },
    {
        "Corpse air is not bravery training. If the smell fades while the bodies remain, leave immediately.",
        "Fresh air is treatment. A proper mask is prevention.",
    },
    {
        "Raw wild game is a parasite lottery. Cook it through, especially rat, boar, bear, fox, and anything scavenged.",
        "If the center is still cold or pink, it is not dinner yet.",
    },
    {
        "Heat kills quietly. Shade, water, and rest are medical supplies when the world temperature climbs.",
        "A hat buys time. It does not make you immortal.",
    },
    {
        "Untreated water can look clean and still ruin you. Boil it when you can.",
        "If your gut turns violent after bad water, hydration becomes the treatment, not a luxury.",
    },
    {
        "A deep wound with glass inside is not just a cut. Remove fragments, disinfect, and keep watching it.",
        "Tetanus is rare until it is yours.",
    },
    {
        "Do not stack serious medication because you are scared. More dose is not more cure.",
        "Follow the interval. Your liver and kidneys are already negotiating with the apocalypse.",
    },
}

local afternoonTalk = {
    {
        "I found a clinic ledger today. Half the handwriting was worse than the injuries.",
        "If you are keeping notes, make them readable. A future you may be the nurse.",
    },
    {
        "Someone once told me surgeons are just mechanics with cleaner tools.",
        "They were wrong. Mechanics get better lighting.",
    },
    {
        "I keep a scalpel wrapped in gauze and a kitchen knife for arguments.",
        "Use the right tool. That sentence applies to medicine and doors.",
    },
    {
        "If you are listening while boiling water, good. If you are listening while drinking river water, we need to talk.",
        "Survival is mostly boring habits done before panic arrives.",
    },
    {
        "I miss hospital coffee. It was terrible, but reliably terrible.",
        "Reliability matters more than taste after the phones go silent.",
    },
    {
        "A patient once asked if stress could kill him. I said yes, but it usually hires accomplices.",
        "Sleep, food, and clean wounds. Start there.",
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
    local index = ((tonumber(day) or 0) + (salt or 0)) % #list
    return list[index + 1]
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

function EHR_RadioMessages.GetDiseaseForDay(day)
    return pick(diseaseEpisodes, day, 0)
end

function EHR_RadioMessages.BuildMorningTip(day)
    local tip = pick(morningTips, day, 1) or morningTips[1]
    return {
        line("<bzzt> The Last Prescription, 147.0. Amelie Crowe speaking.", Colors.STATIC),
        line("Morning rounds, whoever is still alive out there.", Colors.HOST),
        line(tip[1], Colors.TIP),
        line(tip[2], Colors.TIP, "EHX+4"),
        line("Small habits keep big problems from becoming surgery.", Colors.HOST),
    }
end

function EHR_RadioMessages.BuildAfternoonTalk(day)
    local talk = pick(afternoonTalk, day, 3) or afternoonTalk[1]
    return {
        line("<fzzt> The Last Prescription, afternoon check-in.", Colors.STATIC),
        line("Amelie Crowe here. If you can hear me, your radio is doing better than most hospitals.", Colors.HOST),
        line(talk[1], Colors.HOST),
        line(talk[2], Colors.HOST),
        line("Drink water. Check your bandages. Then argue with the day.", Colors.TIP),
    }
end

function EHR_RadioMessages.BuildEveningDisease(day)
    local episode = EHR_RadioMessages.GetDiseaseForDay(day)
    if not episode then return nil end

    return {
        line("<bzzt> The Last Prescription evening pathology note.", Colors.STATIC),
        line("Tonight's file: " .. episode.name .. ".", Colors.MEDICAL),
        line("Cause: " .. episode.cause, Colors.HOST),
        line("Symptoms: " .. episode.symptoms, Colors.WARNING),
        line("Treatment: " .. episode.treatment, Colors.TIP),
        line("Write the name down if you have paper: " .. episode.name .. ".", Colors.MEDICAL, "EHK=" .. episode.id),
    }
end

return EHR_RadioMessages
