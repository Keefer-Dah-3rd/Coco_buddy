import { useId } from "react"
import type { ConceptKey, TimeOfDay, WeatherCondition } from "./App"

type Props = {
  concept: ConceptKey
  done: number
  total: number
  message: string
  time: TimeOfDay
  weather: WeatherCondition
  interactive?: boolean
  onSliderChange?: (value: number) => void
}

const moments = {
  Morning: ["#eef5d9", "#ffde9c", "#b7d482", "#62805a"],
  Daytime: ["#dcecf3", "#f8edce", "#9ac978", "#507358"],
  Evening: ["#c5b9dd", "#ffb68c", "#98936e", "#635c64"],
  Night: ["#242b50", "#626487", "#637c79", "#354f5a"],
}

export default function IllustratedScene({
  concept,
  done,
  total,
  message,
  time,
  weather,
  interactive = true,
  onSliderChange,
}: Props) {
  const id = useId().replace(/:/g, "")
  const night = time === "Night"
  const snow = weather === "Snowy"
  const rain = weather === "Rainy"
  const muted = rain || weather === "Cloudy"
  const [sky, horizon, grass, deep] = moments[time]
  const ground = snow ? "#f2f4ed" : muted ? deep : grass
  const ink = "#1d1f20"
  const accent = "#ff741b"
  const harbourWater = "M0 56C55 58 105 58 160 56S265 54 320 56V108H0Z"
  const awningRoof = "M50 9H263L273 25H40Z"
  const awningScallops = Array.from(
    { length: 14 },
    () => `q${-233 / 28} 6 ${-233 / 14} 0`,
  ).join(" ")
  const clotheslineY = (position: number) => {
    const t = (position - 30) / 259
    return 15 + 44 * t * (1 - t)
  }
  const x = 20 + done * 56
  const common = {
    stroke: ink,
    strokeWidth: 1.25,
    strokeLinecap: "round" as const,
    strokeLinejoin: "round" as const,
  }
  const plant = (px: number, py: number, tall: number, reached: boolean) => (
    <g
      transform={`translate(${px} ${py})`}
      className={weather === "Windy" ? "vector-sway" : ""}
    >
      <path d={`M0 0Q-3 -${tall / 2} 0 -${tall}`} fill="none" />
      <path
        d={`M-1 -${tall * 0.4}Q-18 -${tall * 0.75} -13 -${tall * 0.95}Q2 -${tall * 0.85} -1 -${tall * 0.4}`}
        fill={reached ? "#51e302" : ground}
      />
      <path
        d={`M-1 -${tall * 0.65}Q16 -${tall * 1.1} 13 -${tall * 1.25}Q0 -${tall * 1.2} -1 -${tall * 0.65}`}
        fill={reached ? "#c9df82" : deep}
      />
    </g>
  )

  return (
    <div
      className={`vector-scene vector-${concept} ${
        night ? "vector-night" : ""
      } ${rain ? "vector-rain" : ""}`}
    >
      <svg
        viewBox="0 -44 320 152"
        role="img"
        aria-label={`${done} of ${total} tasks completed. ${message} ${time}, ${weather}.`}
      >
        <defs>
          <linearGradient id={`${id}-sky`} x2="0" y2="1">
            <stop stopColor={muted ? (night ? "#252e41" : "#becdce") : sky} />
            <stop
              offset="1"
              stopColor={muted ? (night ? "#525e6b" : "#dce2da") : horizon}
            />
          </linearGradient>
          <pattern
            id={`${id}-dots`}
            width="5"
            height="5"
            patternUnits="userSpaceOnUse"
          >
            <circle cx="1" cy="1" r=".45" fill={ink} opacity=".12" />
          </pattern>
          <clipPath id={`${id}-clip`}>
            <rect y="-44" width="320" height="152" />
          </clipPath>
          <clipPath id={`${id}-carriage-window`}>
            <rect x="25" y="2" width="269" height="65" rx="15" />
          </clipPath>
          <clipPath id={`${id}-harbour-water`}>
            <path d={harbourWater} />
          </clipPath>
          <clipPath id={`${id}-lighthouse-body`}>
            <path d="m0 41 5-34h13l5 34Z" />
          </clipPath>
          <clipPath id={`${id}-awning-roof`}>
            <path d={awningRoof} />
          </clipPath>
        </defs>
        <g clipPath={`url(#${id}-clip)`}>
          <rect y="-44" width="320" height="152" fill={`url(#${id}-sky)`} />
          <g {...common}>
            {night ? (
              <g fill="#fff2c6">
                <path d="M270 11a12 12 0 1 0 13 17 12 12 0 0 1-13-17Z" />
                {[35, 101, 188, 242, 303].map((p, i) => (
                  <path
                    key={p}
                    d={`M${p} ${12 + (i % 3) * 9}v4m-2-2h4`}
                    stroke="#f3edcf"
                    strokeWidth=".8"
                    className="vector-star"
                  />
                ))}
              </g>
            ) : (
              <circle
                cx={time === "Evening" ? 273 : 260}
                cy={time === "Evening" ? 46 : 23}
                r="13"
                fill="#ffcf71"
              />
            )}
            {(muted || snow) && (
              <g fill={night ? "#737e92" : "#f5f4e9"} className="vector-cloud">
                <path d="M202 28c-6-1-6-9 1-10 0-10 15-12 19-3 9-3 16 4 12 10 6 0 7 7 0 7h-29Z" />
                <path d="M48 19c-2-8 9-12 14-6 1-7 15-8 17 2 9-1 12 10 2 11H50c-7 0-9-6-2-7Z" />
              </g>
            )}

            {concept === "world" && (
              <>
                <path d="M0 76Q65 42 148 65T320 57V108H0Z" fill={ground} />
                <path
                  d="M0 85Q88 59 182 86T320 77V108H0Z"
                  fill={snow ? "#d8e5df" : "#c6d89c"}
                />
                <path
                  d="m81 73 4-43 39-20 39 20 4 43Z"
                  fill={night ? "#d2dab9" : "#ecf4dc"}
                  fillOpacity=".72"
                />
                <path
                  d="m84 31 40 19 39-19m-39-20v62m-40-42 40-20 39 20M83 45l41 19 40-19"
                  fill="none"
                />
                <path d="M87 73h74" strokeWidth="4" />
                {plant(106, 69, 20, done >= 1)}
                {plant(144, 70, 27, done >= 3)}
                <path d="m99 68 3 9h12l3-9Zm36 1 3 8h13l3-8Z" fill="#e4a181" />
                {plant(44, 78, 29, done >= 2)}
                {plant(210, 77, 19, done >= 4)}
                <path
                  d="M229 74h18l-2-12h-11Zm15-10 9-4 6 2-11 8m-17-3h-4v7h5"
                  fill="#ffae79"
                />
                {done === 5 && (
                  <g fill={accent}>
                    <circle cx="43" cy="40" r="4" />
                    <circle cx="208" cy="53" r="4" />
                  </g>
                )}
                <path d="M0 94h320" stroke="#5e795c" strokeWidth=".6" />
              </>
            )}

            {concept === "landscape" && (
              <>
                <path
                  d="m0 64 43-31 29 15 47-31 58 44 36-22 40 17 35-24 32 26v50H0Z"
                  fill={snow ? "#e1e7e3" : "#b2beb0"}
                />
                <path
                  d="m0 76 58-20 49 18 46-33 54 34 49-20 64 25v28H0Z"
                  fill={ground}
                />
                <path
                  d="M320 77Q251 59 199 70T105 70Q58 68 38 85T100 100"
                  stroke={night ? "#d9c6a1" : "#f5dfb4"}
                  strokeWidth="12"
                  fill="none"
                />
                <path
                  d="M320 77Q251 59 199 70T105 70Q58 68 38 85T100 100"
                  stroke="#8b8372"
                  strokeWidth=".7"
                  strokeDasharray="2 5"
                  fill="none"
                />
                <g transform={`translate(${70 + done * 37} 63)`}>
                  <path d="M0 7V-16" fill="none" />
                  <path d="M0-16h14l-4 5 4 4H0Z" fill={accent} />
                </g>
                <g fill={deep}>
                  <path d="m22 68 10-22 10 22H32v10m234-15 8-19 8 19h-8v12" />
                </g>
                <path d="m112 23 7-6 13 10-12-2-6 4Z" fill="#f8f6ec" />
                {time === "Evening" && (
                  <path d="m32 76 42 5m200-6 35 6" stroke={deep} opacity=".4" />
                )}
              </>
            )}

            {concept === "atmospheric" && (
              <>
                <path
                  d="M0 57Q38 52 80 58T160 57T240 58T320 56V108H0Z"
                  fill={night ? "#6c8790" : "#b2d6ca"}
                />
                <path
                  d="M0 73Q40 59 87 72T180 75T270 71T320 74"
                  fill="none"
                  stroke={night ? "#d6e2d4" : "#eff6e1"}
                />
                <path
                  d="M0 88Q46 71 108 87T230 85T320 91V108H0Z"
                  fill={snow ? "#ecf2eb" : "#e7d5a8"}
                />
                <path d="M177 70q18-8 31 3l10 8-20 5-29-6Z" fill="#a6b5a2" />
                <path d="M175 72q10-9 21-3" fill="none" />
                <path d="M45 67v-9l13 4-13 5 7 4h-15Z" fill="#fff8dd" />
                <path
                  d="M87 44h19m-9-4v8m147 12h17m-8-4v8"
                  stroke={night ? "#b8c9c9" : "#f6fbec"}
                  strokeWidth=".7"
                />
                <g transform="translate(235 77)">
                  <path
                    d="m0 0 4-5 4 5 6-2-2 6 4 4-7 1-3 6-3-6-7-1 4-4-2-6Z"
                    fill="#ff9e78"
                  />
                </g>
                {rain && (
                  <g fill="none" stroke="#eff5ec">
                    <ellipse cx="87" cy="75" rx="8" ry="2" />
                    <ellipse cx="275" cy="69" rx="5" ry="1.5" />
                  </g>
                )}
              </>
            )}

            {concept === "coco" && (
              <>
                <path d="M0 0h39v108H0Zm257 0h63v108h-63Z" fill="#eee9d9" />
                <path d="M42 0v76h211V0M146 0v75" fill="none" strokeWidth="3" />
                <path d="M46 63Q87 39 144 60T253 55v21H46Z" fill={ground} />
                <path d="M33 76h231v7H33Z" fill="#f0cf9a" />
                <path
                  d="M0 83h320v25H0Z"
                  fill={night ? "#b5aa9b" : "#efdebd"}
                />
                <g transform="translate(58 58)">
                  {plant(0, 15, 20, done >= 2)}
                  <path d="m-10 13 3 14H7l3-14Z" fill="#d99e7d" />
                </g>
                <path
                  d="M104 88q3-15 32-15h28q30 0 33 15l-7 10h-79Z"
                  fill="#b7b3d9"
                />
                <ellipse
                  cx="150"
                  cy="87"
                  rx="35"
                  ry="7"
                  fill={night ? "#e5dbbb" : "#fff1d7"}
                />
                <path
                  d="m136 85 7-3 8 3 9-3 7 4"
                  stroke="#b5ac9d"
                  fill="none"
                />
                <circle cx={211 + done * 5} cy="91" r="6" fill="#51e302" />
                <path
                  d={`M${208 + done * 5} 86q7 5 2 10`}
                  stroke="#fcffe6"
                  fill="none"
                />
                <path
                  d="M12 27q11 10 8 33M307 27q-11 10-8 33"
                  fill="none"
                  stroke="#b8b29d"
                />
                <path d="M217 70h20l-2-6h-16Z" fill="#ff9d66" />
              </>
            )}

            {concept === "retro" && (
              <>
                <path
                  d="M0 73h320v35H0Z"
                  fill={night ? "#3b416d" : "#c5c1df"}
                />
                <path
                  d="M0 93h320M0 82h320m32-9-22 35m72-35-10 35m72-35v35m72-35 10 35m72-35 22 35"
                  stroke={night ? "#7a7d9c" : "#9a95b5"}
                  strokeWidth=".6"
                />
                <g transform="translate(106 7)">
                  <rect width="107" height="69" rx="10" fill="#fff0c4" />
                  <path
                    d="M9 69V6q0-6 7-6h75"
                    fill="none"
                    stroke="#fffdf4"
                    strokeWidth="2"
                  />
                  <rect
                    x="12"
                    y="9"
                    width="83"
                    height="40"
                    rx="4"
                    fill={night ? "#414864" : "#d9e6c1"}
                  />
                  <path d="m15 43 17-13 12 5 16-15 32 24" fill={ground} />
                  {[0, 1, 2, 3, 4].map((i) => (
                    <rect
                      key={i}
                      x={22 + i * 13}
                      y="22"
                      width="8"
                      height="12"
                      rx="1"
                      fill={i < done ? accent : "#9bac8d"}
                    />
                  ))}
                  <circle cx="24" cy="59" r="4" fill={accent} />
                  <path d="M38 59h20m-10-4v9" />
                  <circle cx="82" cy="59" r="3" fill="#51e302" />
                </g>
                <path
                  d="m42 48 4-7 4 7 8 1-6 5 1 8-7-4-7 4 1-8-6-5Z"
                  fill="#ffb17a"
                />
              </>
            )}

            {concept === "ferry" && (
              <>
                <path
                  d="M0 54Q26 48 47 51L64 40H98L116 52Q166 53 205 48Q239 43 272 50L320 48V64H0Z"
                  fill={ground}
                />
                <path
                  d={harbourWater}
                  fill={night ? "#456777" : rain ? "#82a3a6" : "#b3d9cf"}
                />
                <g transform="translate(219 8)">
                  <path
                    d="m0 41 5-34h13l5 34Z"
                    fill={snow ? "#fff" : "#f4ebd0"}
                    stroke="none"
                  />
                  <g clipPath={`url(#${id}-lighthouse-body)`}>
                    <path d="M0 22h23v7H0Z" fill="#e39778" />
                  </g>
                  <path d="m0 41 5-34h13l5 34Z" fill="none" />
                  <path d="M3 8h17V1H3Zm-2-7 11-8 11 8Z" fill={accent} />
                  <path d="M8 2h7v6H8Z" fill={night ? "#ffe5a0" : "#d2e2da"} />
                  {night && (
                    <path
                      d="M20 3 83-13v35L20 7Z"
                      fill="#fff2c0"
                      opacity=".16"
                      stroke="none"
                    />
                  )}
                </g>
                <path d="M0 83h34v25H0Z" fill="#c7ab89" />
                {[10, 29].map((p) => (
                  <g key={p}>
                    <path d={`M${p} 86V64h6v22Z`} fill="#f8ecce" />
                    <path d={`M${p} 72h6v5h-6Z`} fill={accent} />
                  </g>
                ))}
                <g
                  className="ferry-journey"
                  style={{ transform: `translateX(${35 + done * 32}px)` }}
                >
                  <path
                    d="M-8 79q13 4 27 0m-33 6q9 2 18 0"
                    fill="none"
                    stroke={night ? "#adc9cb" : "#f5fae7"}
                  />
                  <g className="ferry-bob">
                    <path d="M0 64h69l-10 12H12Z" fill={accent} />
                    <path d="M13 64V46h39v18Z" fill="#faf1d7" />
                    <path d="M10 46h47v-5H10Zm23-5V31h8v10Z" fill="#688c89" />
                    {[19, 31, 43].map((p) => (
                      <rect
                        key={p}
                        x={p}
                        y="50"
                        width="7"
                        height="7"
                        rx="1"
                        fill={night ? "#ffdc91" : "#a8ccd1"}
                      />
                    ))}
                    <circle cx="16" cy="68" r="3" fill="#f6eddb" />
                    <circle cx="53" cy="68" r="3" fill="#f6eddb" />
                  </g>
                </g>
                <path
                  d="M259 84q9 2 18 0M138 88q11 2 22 0M256 64q10 2 20 0M63 91q9 2 18 0"
                  stroke={night ? "#9dbdc1" : "#edf6e0"}
                  strokeWidth=".8"
                  clipPath={`url(#${id}-harbour-water)`}
                  fill="none"
                />
              </>
            )}

            {concept === "bookshop" && (
              <>
                <path
                  d="M0 82h320v26H0Z"
                  fill={rain ? "#9faeaa" : snow ? "#e8eeeb" : "#d3c7ad"}
                />
                <path
                  d="M48 82V9h217v73Z"
                  fill={night ? "#a3afa5" : "#ece4ce"}
                />
                <path
                  d={`M50 9H263L273 25V31${awningScallops}V25Z`}
                  fill="#f6eddb"
                  stroke="none"
                />
                <g clipPath={`url(#${id}-awning-roof)`}>
                  {[0, 2, 4, 6, 8, 10, 12].map((i) => (
                    <path
                      key={i}
                      d={`M${50 + (i * 213) / 14} 9H${50 + ((i + 1) * 213) / 14}L${40 + ((i + 1) * 233) / 14} 25H${40 + (i * 233) / 14}Z`}
                      fill="#bc7b64"
                      stroke="none"
                    />
                  ))}
                  {Array.from({ length: 13 }, (_, i) => i + 1).map((i) => (
                    <path
                      key={i}
                      d={`M${50 + (i * 213) / 14} 9L${40 + (i * 233) / 14} 25`}
                      fill="none"
                      strokeWidth=".7"
                    />
                  ))}
                </g>
                <path
                  d={`M50 9H263L273 25V31${awningScallops}V25Z`}
                  fill="none"
                />
                <path d="M40 25H273" fill="none" />
                {[0, 1, 2, 3, 4].map((i) => (
                  <g key={i} transform={`translate(${61 + i * 37} 37)`}>
                    <path
                      d="M0 42V12a14 14 0 0 1 28 0v30Z"
                      fill={
                        done > i ? "#ffdc9f" : night ? "#3d4b60" : "#bdcfc2"
                      }
                    />
                    <path d="M0 27h28" strokeWidth=".8" />
                    {[0, 1, 2].map((b) => (
                      <path
                        key={b}
                        d={`m${5 + b * 7} 37v-7h4v7Z`}
                        fill={["#d89574", "#889b82", "#d4bd8b"][b]}
                        strokeWidth=".7"
                      />
                    ))}
                    <path d="M14-2v28" strokeWidth=".7" />
                  </g>
                ))}
                <path d="M47 80h219v5H47Z" fill="#b98d6b" />
                <path d="M282 82V58h20v24Zm-3-24 13-8 13 8Z" fill="#f9edd1" />
                <path d="M286 65h13m-13 5h10m-10 5h12" strokeWidth=".7" />
                <path d="M21 81V61m-9 4q10 12 9-11 13 10 3 18" fill={ground} />
                <path d="m11 76 3 10h14l3-10Z" fill="#cc9477" />
                {rain && (
                  <ellipse
                    cx="283"
                    cy="89"
                    rx="17"
                    ry="2"
                    fill="#b8ced0"
                    strokeWidth=".7"
                  />
                )}
              </>
            )}

            {concept === "rooftop" && (
              <>
                <path
                  d="M0 74V48h24v-9h24v35m16 0V30h27v44m112 0V44h22v-8h30v38m16 0V24h27v50"
                  fill={night ? "#566378" : "#c5c7be"}
                  strokeWidth=".7"
                />
                <path
                  d="M0 82h320v26H0Z"
                  fill={snow ? "#f0f3e9" : rain ? "#9d9f96" : "#d6bba1"}
                />
                <path d="M0 75h320v8H0Z" fill="#b5b29f" />
                <path d="M29 77V5m261 72V5M30 15q129.5 22 259 0" fill="none" />
                {[0, 1, 2, 3, 4].map((i) => {
                  const left = 49 + i * 43
                  const top = clotheslineY(left)
                  const rightOffset = clotheslineY(left + 23) - top
                  return (
                    <g key={i} transform={`translate(${left} ${top})`}>
                      <path
                        d={`M0-5v9M23 ${rightOffset - 5}v9`}
                        stroke="#9a7055"
                        strokeWidth="3"
                      />
                      {done > i ? (
                        <g
                          className={weather === "Windy" ? "hanging-linen" : ""}
                        >
                          {i % 2 === 0 ? (
                            <path
                              d="m-2 0 7-3 7 3 7-3 7 3 6 12-7 3-2-4 1 26H0l1-26-3 4-7-3Z"
                              fill={
                                [
                                  "#f9edcf",
                                  "#c4d4c1",
                                  "#dfa58a",
                                  "#b7bdd4",
                                  "#f4da9c",
                                ][i]
                              }
                            />
                          ) : (
                            <path
                              d="M-2-2q14 4 29 0l-1 38q-14-5-26 0Z"
                              fill={i === 1 ? "#a6bab2" : "#b8afd0"}
                            />
                          )}
                          <path
                            d="M5 5v23m14-22v20"
                            strokeWidth=".6"
                            opacity=".4"
                            fill="none"
                          />
                        </g>
                      ) : (
                        <path d="M0 2h23" strokeDasharray="2 3" opacity=".35" />
                      )}
                    </g>
                  )
                })}
                <path d="M22 87h30v-9H22Zm5-9h23v-5H27Z" fill="#e9dfc2" />
                <path d="m266 80 4 10h21l4-10Z" fill="#ce9675" />
                <path
                  d="M280 80V60m0 12q-18-3-14-12 12 1 14 12m0-4q15-19 19-9-6 11-19 9"
                  fill={ground}
                />
                <path d="M93 87h33m90 0h17" stroke="#b49b82" strokeWidth=".7" />
              </>
            )}

            {concept === "train" && (
              <>
                <rect
                  y="-44"
                  width="320"
                  height="152"
                  fill={night ? "#485663" : "#e5dbc6"}
                  stroke="none"
                />
                <g clipPath={`url(#${id}-carriage-window)`}>
                  <rect
                    x="25"
                    y="2"
                    width="269"
                    height="65"
                    fill={`url(#${id}-sky)`}
                    stroke="none"
                  />
                  {night ? (
                    <path
                      d="M270 11a10 10 0 1 0 10 14 10 10 0 0 1-10-14Z"
                      fill="#fff2c6"
                    />
                  ) : (
                    <circle
                      cx="263"
                      cy={time === "Evening" ? 34 : 19}
                      r="10"
                      fill="#ffcf71"
                    />
                  )}
                  <path d="M20 42q53-26 99-4t84 1 99-8v44H20Z" fill={ground} />
                  <path
                    d="M20 56q67-15 122-1t160-5v25H20Z"
                    fill={snow ? "#e9eee5" : deep}
                  />
                  <g
                    className="carriage-scenery"
                    fill={night ? "#a1aa9a" : "#e5d7b4"}
                  >
                    <path d="m47 48 10-8 10 8v11H47Zm2 0h16m153-7 10-8 10 8v16h-20Z" />
                    <path d="M56 49v6m171-12v7" stroke="#fff0bf" />
                  </g>
                </g>
                <rect
                  x="25"
                  y="2"
                  width="269"
                  height="65"
                  rx="15"
                  fill="none"
                />
                <path
                  d="M26 66h268v7H26ZM111 3v63m95-63v63"
                  fill="#b49a79"
                  strokeWidth="2"
                />
                <path
                  d="M0 79q20-16 56 0v29H0Zm260 0q30-16 60 0v29h-60Z"
                  fill={night ? "#697988" : "#9aaba1"}
                />
                <path d="M8 83h37m227 0h40" stroke="#d9d9c2" strokeWidth=".7" />
                <path
                  d="M79 80h160l9 6H70Zm24 6-3 22m114-22 3 22"
                  fill="#d6b78f"
                />
                <path
                  d="M171 76h31m-27-1-2-15h22l-2 15Zm20-14q15-3 10 8l-11 2"
                  fill="#f9efd8"
                />
                <path
                  d="M180 55q-5-4 0-8m7 8q-4-4 0-8"
                  fill="none"
                  stroke={night ? "#fff0d0" : "#8e9e90"}
                  className="tea-steam"
                />
                <rect
                  x="108"
                  y="74"
                  width="40"
                  height="7"
                  rx="1"
                  fill="#f5e3b3"
                />
                {[0, 1, 2, 3, 4].map((i) => (
                  <circle
                    key={i}
                    cx={113 + i * 7}
                    cy="77.5"
                    r="1.4"
                    fill={done > i ? accent : "#d9ccb0"}
                    strokeWidth=".5"
                  />
                ))}
              </>
            )}

            {concept === "pottery" && (
              <>
                <path
                  d="M0 0h320v108H0Z"
                  fill={night ? "#a3aaa0" : "#eee5d4"}
                />
                <rect
                  x="203"
                  y="1"
                  width="91"
                  height="57"
                  rx="4"
                  fill={`url(#${id}-sky)`}
                />
                <path d="M204 45q25-20 45-7t44-3v23h-89Z" fill={ground} />
                <path
                  d="M248 2v55m-44-28h88m-94 29h101v5H198Z"
                  fill="#c9b697"
                />
                {rain && (
                  <path
                    d="m216 9-2 7m51-5-2 7m13 18-2 7m-42-8-2 7"
                    stroke="#708e94"
                    fill="none"
                  />
                )}
                <path
                  d="M0 75h320v33H0Z"
                  fill={night ? "#99988c" : "#d1c5ae"}
                />
                <path d="M15 65h279v9H15Zm8 9v34m260-34v34" fill="#d3ac83" />
                {[0, 1, 2, 3, 4].map((i) => (
                  <g key={i} transform={`translate(${47 + i * 35} 63)`}>
                    <path
                      d={
                        i % 2 === 0
                          ? "M-8 0q-5-11 0-19l2-8H6l2 8q5 8 0 19Z"
                          : "M-10 0q-5-9-3-16h26q2 7-3 16Z"
                      }
                      fill={
                        done > i
                          ? [
                              "#e0a278",
                              "#9eafa1",
                              "#b8b0c9",
                              "#dfb978",
                              "#a6c6bf",
                            ][i]
                          : "#c5a48c"
                      }
                    />
                    <ellipse
                      cy={i % 2 === 0 ? -27 : -16}
                      rx={i % 2 === 0 ? 6 : 13}
                      ry="2"
                      fill={done > i ? "#f3e5cb" : "#ad8b74"}
                      strokeWidth=".7"
                    />
                    {done > i && (
                      <path
                        d="M-6-8h12m-11 3h10"
                        stroke="#f7edd6"
                        opacity=".65"
                        strokeWidth=".8"
                      />
                    )}
                  </g>
                ))}
                <ellipse cx="245" cy="85" rx="29" ry="7" fill="#e4d4b7" />
                <path d="M237 84q-7-15 0-21h15q6 7 0 21Z" fill="#ba9278" />
                <ellipse cx="244.5" cy="63" rx="7.5" ry="2.5" fill="#a17c64" />
                <path d="M236 89v19m17-19v19" strokeWidth="2" />
                <path d="M23 18h143v4H23Z" fill="#bca184" />
                <path
                  d="M35 17V8h17v9m16 0V1h10v16m17 0V6h20v11"
                  fill="#c5b29b"
                />
                <path
                  d="M18 85h35m-31-4 28 9"
                  stroke="#937a60"
                  strokeWidth="2"
                />
              </>
            )}

            <rect
              width="320"
              height="108"
              fill={`url(#${id}-dots)`}
              stroke="none"
            />
            <g
              clipPath={
                concept === "train" ? `url(#${id}-carriage-window)` : undefined
              }
            >
              {snow && (
                <path
                  d="M0 75q10-4 19 0t20 0m161 1q12-5 24-1m50-4q18-5 46 0"
                  stroke="#fffdf5"
                  strokeWidth="5"
                />
              )}
              {(rain || snow) && (
                <g
                  className={rain ? "vector-rainfall" : "vector-snowfall"}
                  stroke={night ? "#e6f0ee" : "#5f8090"}
                >
                  {Array.from({ length: 12 }, (_, i) =>
                    rain ? (
                      <path
                        key={i}
                        d={`m${i * 29 - 6} ${(i % 3) * 17} -3 8`}
                        strokeWidth=".8"
                      />
                    ) : (
                      <circle
                        key={i}
                        cx={i * 29 - 6}
                        cy={(i % 3) * 17}
                        r="1.6"
                        fill="#fff"
                        strokeWidth=".5"
                      />
                    ),
                  )}
                </g>
              )}
              {weather === "Windy" && (
                <g
                  className="vector-gust"
                  fill="none"
                  stroke={night ? "#d5d9de" : "#71867c"}
                  strokeWidth=".8"
                >
                  <path d="M9 31h36q9 0 7-5m178 17h30q10 0 7-6M79 14h23" />
                  <path d="m230 27 6-3 2 4-6 3Z" fill="#ffb17a" />
                </g>
              )}
            </g>
          </g>
          <g fill={night ? "#fff5dc" : ink} className="scene-task-copy">
            <text x="18" y="-10" fontSize="30" fontWeight="500">
              {done}
              <tspan fontSize="14" fontWeight="400">
                /{total}
              </tspan>
            </text>
            <text
              x="78"
              y="-32"
              dominantBaseline="text-before-edge"
              fontSize="10"
              opacity=".78"
            >
              {message}
            </text>
            <text
              x="301"
              y="-32"
              dominantBaseline="text-before-edge"
              textAnchor="end"
              fontSize="6.5"
              letterSpacing=".4"
            >
              {time.toUpperCase()} · {weather.toUpperCase()}
            </text>
            <text x="301" y="-12" textAnchor="end" fontSize="7" opacity=".72">
              {done === total ? "All complete" : `${total - done} remaining`}
            </text>
          </g>
          {/* The draggable track is part of the foreground, not a second meter. */}
          <g {...common} transform="translate(0 0)">
            <rect
              x="20"
              y="96"
              width="280"
              height="5"
              rx="2.5"
              fill={concept === "retro" ? "#72728c" : "#f6f1de"}
            />
            <rect
              x="20"
              y="96"
              width={Math.max(0, done * 56)}
              height="5"
              rx="2.5"
              fill={accent}
              stroke="none"
            />
            {[1, 2, 3, 4, 5].map((i) => (
              <path
                key={i}
                d={`M${20 + i * 56} 97v3`}
                stroke={i < done ? "#ffe5ba" : ink}
                strokeWidth=".7"
              />
            ))}
            <g
              className="vector-thumb"
              style={{ transform: `translateX(${x}px)` }}
            >
              {concept === "bookshop" ? (
                <path d="M-5 91H5v15l-5-3-5 3Z" fill="#e6a17b" />
              ) : concept === "rooftop" ? (
                <g>
                  <rect
                    x="-4"
                    y="90"
                    width="8"
                    height="16"
                    rx="2"
                    fill="#ddbd8e"
                  />
                  <path d="M0 94v7" />
                </g>
              ) : concept === "ferry" ? (
                <g>
                  <path d="M-5 102v-7a5 5 0 0 1 10 0v7Z" fill={accent} />
                  <path d="M-5 98H5" stroke="#fff5dc" strokeWidth="2" />
                  <path d="M-7 103H7" />
                </g>
              ) : concept === "pottery" ? (
                <g>
                  <ellipse cy="98.5" rx="8" ry="6" fill="#ca9675" />
                  <path d="M-4 98q4 3 8 0" fill="none" stroke="#f8dec1" />
                </g>
              ) : concept === "retro" || concept === "train" ? (
                <g>
                  <rect
                    x="-7"
                    y="91"
                    width="14"
                    height="14"
                    rx="3"
                    fill="#ffcf71"
                  />
                  <path d="M-2 95v6m4-6v6" strokeWidth=".8" />
                </g>
              ) : (
                <g>
                  <circle
                    cy="98.5"
                    r="7"
                    fill={concept === "coco" ? "#51e302" : "#fff9e9"}
                  />
                  {concept === "coco" ? (
                    <path d="M-3 92q6 6 0 13" fill="none" stroke="#fff" />
                  ) : (
                    <circle cy="98.5" r="2" fill={accent} stroke="none" />
                  )}
                </g>
              )}
            </g>
          </g>
        </g>
      </svg>
      {interactive && (
        <input
          type="range"
          min="0"
          max="5"
          step="1"
          value={done}
          onChange={(event) => onSliderChange?.(Number(event.target.value))}
          aria-label={`Task progress, ${done} of 5 completed`}
          className="vector-slider-input"
        />
      )}
    </div>
  )
}
