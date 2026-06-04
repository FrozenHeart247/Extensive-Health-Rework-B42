EHR = EHR or {}
RecipeCodeOnTest = RecipeCodeOnTest or {}

local freshMedicinalIngredients = {
    ["Base.Garlic"] = true,
    ["Base.WildGarlic2"] = true,
    ["Base.Oregano"] = true,
    ["Base.Thyme"] = true,
    ["Base.Lavender"] = true,
    ["Base.GingerRoot"] = true,
    ["Base.Plantain"] = true,
    ["Base.Comfrey"] = true,
    ["Base.Marigold"] = true,
}

function RecipeCodeOnTest.EHRFreshMedicinalIngredients(item)
    if not item then return true end

    local typeOk, fullType = pcall(function() return item:getFullType() end)
    if not typeOk then return true end

    if not freshMedicinalIngredients[fullType] then
        return true
    end

    local isFresh = true
    local isRotten = false

    local freshOk, freshResult = pcall(function() return item:isFresh() end)
    if freshOk then isFresh = freshResult == true end

    local rottenOk, rottenResult = pcall(function() return item:isRotten() end)
    if rottenOk then isRotten = rottenResult == true end

    return isFresh and not isRotten
end
