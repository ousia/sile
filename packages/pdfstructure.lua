local stPointer
local stNode = function(t) return {
  t = t,
  lang = SILE.settings.get("document.language"),
  kids = {},
  parent = stPointer
}
end

SILE.require("packages/pdf")
local pdf = require("justenoughlibtexpdf")

local stRoot = stNode("Document")
stPointer = stRoot
local mcid = 0

local addChild = function(node)
  stPointer.kids[#(stPointer.kids)+1] = node
  node.parent = stPointer
end

local actualtext = {}

SILE.registerCommand("pdf:structure", function (o,c)
  local t = SU.required(o,"type", "pdf structure")
  local node = stNode(t)
  addChild(node)
  node.lang = SILE.settings.get("document.language")
  node.page = pdf.get_dictionary("@THISPAGE")
  node.mcid = mcid
  local oldstPointer = stPointer
  stPointer = node
  actualtext[#actualtext+1] = ""
  if not o.block then
    SILE.call("pdf:literal",{},{"/"..t.." <</MCID "..mcid.." >>BDC"})
    mcid = mcid + 1
    SILE.process(c)
    SILE.call("pdf:literal",{},{"EMC"})
  else
    SILE.process(c)
  end
  stPointer.actualtext = actualtext[#actualtext]
  actualtext[#actualtext] = nil
  stPointer = oldstPointer
end)

SILE.typesetter.typeset = function(self, text)
  actualtext[#actualtext] = actualtext[#actualtext] .. text
  SILE.defaultTypesetter.typeset(self, text)
end

local structureNumberTree
local numberTreeIndex = 0
local ensureStructureNumber = function ( node, pdfnode )
  local p = node.page
  if not pdf.lookup_dictionary(p, "StructParents") then
    pdf.add_dict(p,pdf.parse("/StructParents"),pdf.parse(numberTreeIndex))
    local nums = pdf.lookup_dictionary(structureNumberTree, "Nums")
    pdf.push_array(nums, pdf.parse(numberTreeIndex))
    pdf.push_array(nums, pdf.parse("[]"))
    numberTreeIndex = numberTreeIndex + 1
  end
  local nums = pdf.lookup_dictionary(structureNumberTree, "Nums")
  -- This is an array and its last element is an array
  local r = pdf.get_array(nums, pdf.array_length(nums)-1)
  pdf.push_array(r, pdf.reference(pdfnode))
end

local dumpTree

dumpTree = function (node)
  local k = {}
  local pdfNode = pdf.parse("<< /Type /StructElem /S /"..(node.t)..">>")
  if #(node.kids) > 0 then
    for i = 1,#(node.kids) do
      k[#k+1] = dumpTree(node.kids[i])
    end
    local kArray = pdf.parse("[]")
    for i = 1,#k do pdf.push_array(kArray, k[i]) end
    pdf.add_dict(pdfNode, pdf.parse("/K"), kArray)
  else
    pdf.add_dict(pdfNode, pdf.parse("/K"), pdf.parse(node.mcid))
  end
  if node.page then
    pdf.add_dict(pdfNode, pdf.parse("/Pg"), pdf.reference(node.page))
    ensureStructureNumber(node, pdfNode)
  end
  if node.lang then
    pdf.add_dict(pdfNode, pdf.parse("/Lang"), pdf.parse("("..node.lang:upper()..")"))
  end

  if node.actualtext then
    pdf.add_dict(pdfNode, pdf.parse("/ActualText"), pdf.string(node.actualtext))
  end
  local ref = pdf.reference(pdfNode)
  pdf.release(pdfNode)
  return ref
end


SILE.outputters.libtexpdf.finish = function()
  pdf.endpage()
  local c = pdf.get_dictionary("Catalog")
  structureTree = pdf.parse("<< /Type /StructTreeRoot >>")
  pdf.add_dict(c,pdf.parse("/StructTreeRoot"),pdf.reference(structureTree))
  structureNumberTree = pdf.parse("<< /Nums [] >>")
  pdf.add_dict(structureTree,pdf.parse("/ParentTree"),pdf.reference(structureNumberTree))

  pdf.add_dict(structureTree, pdf.parse("/K"), dumpTree(stRoot))

  if structureNumberTree then pdf.release(structureNumberTree) end
  if structureTree then pdf.release(structureTree) end
  pdf.finish()
end