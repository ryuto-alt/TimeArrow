-- TitleLogoIntro.lua -- タイトルロゴ演出ディレクター。
-- 文字(TitleChar1..9)が1文字ずつ上から弾んで落ちてきて、最後に矢(TitleArrow)が
-- 左から高速で飛び込み、着弾の衝撃で文字列が波打つ。以降は文字ごとに位相を
-- ずらした波モーションでアイドル。各エンティティのJSON上のtransformを基準値とする。
properties = {
  { name = "charDelay",  type = "float", default = 0.09, min = 0,   max = 1, label = "文字の時間差(秒)" },
  { name = "dropHeight", type = "float", default = 2.4,  min = 0,   max = 10, label = "落下開始の高さ" },
  { name = "waveAmp",    type = "float", default = 0.06, min = 0,   max = 1, label = "アイドル波の振れ幅" },
}

local CHAR_COUNT = 9
local CHAR_DUR   = 0.5   -- 1文字の登場時間
local FIRST_AT   = 0.3   -- 最初の文字が出るまで
local ARROW_FLY  = 0.32  -- 矢の飛来時間
local ARROW_BACK = 0.3   -- 矢のリコイル戻り時間
local SQUASH_DUR = 0.32  -- 着弾スカッシュ時間

local function clamp01(x) if x < 0 then return 0 elseif x > 1 then return 1 end return x end
local function easeOutCubic(u) local v = 1 - u; return 1 - v * v * v end
local function easeOutBack(u)
  local c1, c3 = 1.70158, 2.70158
  local v = u - 1
  return 1 + c3 * v * v * v + c1 * v * v
end
local function easeInOutQuad(u)
  if u < 0.5 then return 2 * u * u end
  return 1 - (-2 * u + 2) ^ 2 / 2
end

function OnStart(self)
  self.clock = 0
  self.chars = {}
  for i = 1, CHAR_COUNT do
    local e = scene:findEntity("TitleChar" .. i)
    if e and e:isValid() then
      local t = e.transform
      self.chars[i] = {
        ent = e,
        px = t.position.x, py = t.position.y, pz = t.position.z,
        sx = t.scale.x,    sy = t.scale.y,    sz = t.scale.z,
      }
    end
  end
  local a = scene:findEntity("TitleArrow")
  if a and a:isValid() then
    local t = a.transform
    self.arrow = { ent = a, px = t.position.x, py = t.position.y, pz = t.position.z }
  end
end

function OnUpdate(self, dt)
  self.clock = self.clock + dt
  local t = self.clock

  local arrowAt   = FIRST_AT + self.charDelay * CHAR_COUNT + 0.05
  local impactAt  = arrowAt + ARROW_FLY
  local idleAt    = impactAt + SQUASH_DUR
  local idleT     = t - idleAt
  local idleRamp  = clamp01(idleT / 0.6)   -- アイドル波はなめらかに立ち上げる

  -- ── 文字 ──────────────────────────────────────────
  for i, c in pairs(self.chars) do
    local born = FIRST_AT + self.charDelay * (i - 1)
    local u = clamp01((t - born) / CHAR_DUR)

    local x, y, rz = c.px, c.py, 0
    local s = 0.0001
    if u > 0 then
      s = c.sx * easeOutBack(u)
      y = c.py + (1 - easeOutCubic(u)) * self.dropHeight
      local alt = (i % 2 == 0) and 1 or -1
      rz = (1 - easeOutCubic(u)) * 18 * alt
    end

    -- 着弾スカッシュ: 矢が刺さった衝撃が左から右へ走る
    local sq = clamp01((t - impactAt - (i - 1) * 0.02) / SQUASH_DUR)
    local squash = 0
    if sq > 0 and sq < 1 then squash = math.sin(sq * math.pi) end

    -- アイドル: 文字ごとに位相をずらした波
    if idleT > 0 then
      y = y + math.sin(idleT * 2.1 + i * 0.55) * self.waveAmp * idleRamp
      rz = rz + math.sin(idleT * 1.4 + i * 0.7) * 2.2 * idleRamp
    end

    c.ent.transform.position = Vec3.new(x, y - squash * 0.1, c.pz)
    c.ent.transform.rotation = Vec3.new(0, 0, rz)
    c.ent.transform.scale    = Vec3.new(s, s * (1 - squash * 0.22), s)
  end

  -- ── 矢 ────────────────────────────────────────────
  if self.arrow then
    local a = self.arrow
    local x, y, rz = a.px, a.py, 0
    if t < arrowAt then
      x = a.px - 40   -- 画面外左で待機
    elseif t < impactAt then
      local u = clamp01((t - arrowAt) / ARROW_FLY)
      x = (a.px - 40) + (40 + 0.9) * easeOutCubic(u)   -- 高速飛来+0.9オーバーシュート
      rz = -6 * (1 - u)
    elseif t < impactAt + ARROW_BACK then
      local u = clamp01((t - impactAt) / ARROW_BACK)
      x = a.px + 0.9 * (1 - easeInOutQuad(u))          -- リコイルで定位置へ
    end
    if idleT > 0 then
      y = y + math.sin(idleT * 1.7) * 0.05 * idleRamp
      x = x + math.sin(idleT * 0.9) * 0.08 * idleRamp
      rz = rz + math.sin(idleT * 0.8) * 1.0 * idleRamp
    end
    a.ent.transform.position = Vec3.new(x, y, a.pz)
    a.ent.transform.rotation = Vec3.new(0, 0, rz)
  end
end
