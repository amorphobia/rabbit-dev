/*
 * Copyright (c) 2025 Xuesong Peng <pengxuesong.cn@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#Include <RabbitUIStyle>
#Include <RabbitMonitors>
#Include <Gdip\Gdip_All>
#Include <RabbitCaret>

; https://learn.microsoft.com/windows/win32/winmsg/extended-window-styles
global WS_EX_NOACTIVATE := "+E0x8000000"
global WS_EX_COMPOSITED := "+E0x02000000"
global WS_EX_LAYERED    := "+E0x00080000"

class CandidateBoxEx {
    static dbg := false
    static gui := 0
    static pToken := Gdip_Startup()

    __New() {
        this.UpdateUIStyle()
    }

    UpdateUIStyle() {
        local hWnd := WinExist("A")
        local hMond := MonitorManage.MonitorFromWindow(hWnd)
        local info := MonitorManage.GetMonitorInfo(hMond)

        if info {
            CandidateBoxEx.canvas_width := info.work.right - info.work.left
            CandidateBoxEx.canvas_height := info.work.bottom - info.work.top
        } else {
            CandidateBoxEx.canvas_width := SysGet(16) ; SM_CXFULLSCREEN
            CandidateBoxEx.canvas_height := SysGet(17) ; SM_CYFULLSCREEN
        }
    }

    Build(context, &width?, &height?) {
        if !CandidateBoxEx.gui || !CandidateBoxEx.gui.built
            CandidateBoxEx.gui := CandidateBoxEx.BoxGui()
        CandidateBoxEx.gui.Build(context)
        width := CandidateBoxEx.gui.width
        height := CandidateBoxEx.gui.height
    }

    Show(x, y) {
        if CandidateBoxEx.gui && CandidateBoxEx.gui.built
            CandidateBoxEx.gui.Show(x, y)
    }

    Hide() {
        if CandidateBoxEx.gui && CandidateBoxEx.gui.built
            CandidateBoxEx.gui.Hide()
    }

    class BoxGui extends Gui {
        built := false
        __New() {
            super.__New(, , this)
            this.Opt(Format("-DPIScale -Caption +Owner +AlwaysOnTop {} {} {}", WS_EX_NOACTIVATE, WS_EX_COMPOSITED, WS_EX_LAYERED))

            if !CandidateBoxEx.pToken {
                if !CandidateBoxEx.pToken := Gdip_Startup()
                    return ; TODO: fallback
            }

            this.font_size := CandidateBoxEx.Pt2Px(UIStyle.font_point)
            this.label_font_size := CandidateBoxEx.Pt2Px(UIStyle.label_font_point)
            this.comment_font_size := CandidateBoxEx.Pt2Px(UIStyle.comment_font_point)

            this.hbm := CreateDIBSection(CandidateBoxEx.canvas_width, CandidateBoxEx.canvas_height)
            this.hdc := CreateCompatibleDC()
            this.obm := SelectObject(this.hdc, this.hbm)
            this.G := Gdip_GraphicsFromHDC(this.hdc)
            Gdip_SetSmoothingMode(this.G, 4)

            ; check font
            if !f := Gdip_FontFamilyCreate(UIStyle.font_face)
                UIStyle.font_face := "Microsoft YaHei UI"
            Gdip_DeleteFontFamily(f)
            if !f := Gdip_FontFamilyCreate(UIStyle.label_font_face)
                UIStyle.label_font_face := UIStyle.font_face
            Gdip_DeleteFontFamily(f)
            if !f := Gdip_FontFamilyCreate(UIStyle.comment_font_face)
                UIStyle.comment_font_face := UIStyle.font_face
            Gdip_DeleteFontFamily(f)
        }

        __Delete() {
            if this.hbm {
                DeleteObject(this.hbm)
                this.hbm := 0
            }
            if this.hdc {
                DeleteDC(this.hdc)
                this.hdc := 0
            }
            if this.G {
                Gdip_DeleteGraphics(this.G)
                this.G := 0
            }
        }

        Build(context) {
            if !this.G || !context
                return

            ; Gdip_GraphicsClear(this.G)
            local tool_mode := A_CoordModeToolTip
            if GetCaretPosEx(&cl, &ct, &cr, &cb) {
                A_CoordModeToolTip := "Screen"
                ToolTip(this.Hwnd, cl, cb, 15)
            }
            A_CoordModeToolTip := tool_mode

            menu := context.menu
            local candidates := menu.candidates
            local num_candidates := menu.num_candidates
            local hilited_index := menu.highlighted_candidate_index + 1
            local composition := context.composition

            CandidateBoxEx.BuildPreedit(composition, &pre, &sel, &post)

            ; measure preedit
            local preW := 0, preH := 0, selW := 0, selH := 0, postW := 0, postH := 0
            local preedit_width := 0
            if pre {
                opt := Format("x0 y0 Left r4 s{}", this.font_size)
                this.MeasureText(pre, opt, UIStyle.font_face, &preW, &preH)
                preedit_width += (preW + UIStyle.margin_x)
            }
            if sel {
                opt := Format("x0 y0 Left r4 s{}", this.font_size)
                this.MeasureText(sel, opt, UIStyle.font_face, &selW, &selH)
                preedit_width += (selW + UIStyle.margin_x * 2)
            }
            if post {
                opt := Format("x0 y0 Left r4 s{}", this.font_size)
                this.MeasureText(post, opt, UIStyle.font_face, &postW, &postH)
                preedit_width += (postW + UIStyle.margin_x)
            }
            local preedit_height := max(preH, selH, postH) + UIStyle.margin_y * 2

            ; measure candidates
            this.has_comment := false
            local max_label_width := 0
            local max_candidate_width := 0
            local max_comment_width := 0
            local candidate_height := -UIStyle.margin_y
            local has_label := !!context.select_labels[0]
            local select_keys := menu.select_keys
            local num_select_keys := StrLen(select_keys)
            local candidate_line_height := []
            local labels := []
            local cands := []
            local comments := []
            loop num_candidates {
                local label_text := String(A_Index)
                if A_Index <= menu.page_size && has_label {
                    local l := context.select_labels[A_Index]
                    label_text := l ? l : label_text
                } else if A_Index <= num_select_keys {
                    label_text := SubStr(select_keys, A_Index, 1)
                }
                label_text := Format(UIStyle.label_format, label_text)
                labels.Push(label_text)
                opt := Format("x0 y0 Right r4 s{}", this.label_font_size)
                this.MeasureText(label_text, opt, UIStyle.label_font_face, &w, &h1)
                ; including margin between label and candidate
                max_label_width := max(max_label_width, w + UIStyle.margin_x * 2)

                local candidate := candidates[A_Index].text
                cands.Push(candidate)
                opt := Format("x0 y0 Left r4 s{}", this.font_size)
                this.MeasureText(candidate, opt, UIStyle.font_face, &w, &h2)
                max_candidate_width := max(max_candidate_width, w)

                if comment_text := candidates[A_Index].comment
                    this.has_comment := true
                comments.Push(comment_text)
                opt := Format("x0 y0 Left r4 s{}", this.comment_font_size)
                this.MeasureText(comment_text, opt, UIStyle.comment_font_face, &w, &h3)
                ; including margin between candidate and comment
                max_comment_width := max(max_comment_width, w + UIStyle.margin_x * 2)

                candidate_height += (UIStyle.margin_y * 2 + max(h1, h2, h3))
                candidate_line_height.Push(UIStyle.margin_y * 2 + max(h1, h2, h3))
            }

            local box_width := max_label_width + max_candidate_width + this.has_comment * max_comment_width + UIStyle.border_width * 2

            local req_width := max(UIStyle.min_width, box_width, preedit_width)
            if box_width < req_width {
                max_candidate_width += (req_width - box_width)
                box_width := req_width
            }
            if preedit_width < req_width {
                ; TODO: maybe need to handle
            }

            local box_height := preedit_height + candidate_height + UIStyle.border_width * 2

            ; draw background
            local pBrush := Gdip_BrushCreateSolid(UIStyle.back_color)
            Gdip_FillRoundedRectangle(this.G, pBrush, 0, 0, box_width, box_height, UIStyle.round_corner)
            Gdip_DeleteBrush(pBrush)

            ; draw background border
            local pPen := Gdip_CreatePen(UIStyle.border_color, UIStyle.border_width)
            Gdip_DrawRoundedRectangle(this.G, pPen, 0, 0, box_width, box_height, UIStyle.round_corner)
            Gdip_DeletePen(pPen)

            ; starting
            local xcoor := UIStyle.border_width
            local ycoor := UIStyle.border_width

            if pre {
                opt := Format("x{} y{} Left c{:x} r4 s{}", xcoor + UIStyle.margin_x, ycoor + UIStyle.margin_y, UIStyle.text_color, this.font_size)
                Gdip_TextToGraphics(this.G, pre, opt, UIStyle.font_face, CandidateBoxEx.canvas_width, CandidateBoxEx.canvas_height)
                xcoor += preW
            }
            if sel {
                pBrush := Gdip_BrushCreateSolid(UIStyle.hilited_back_color)
                Gdip_FillRoundedRectangle(this.G, pBrush, xcoor, ycoor, selW + UIStyle.margin_x * 2, preedit_height, UIStyle.round_corner)
                Gdip_DeleteBrush(pBrush)

                opt := Format("x{} y{} Left c{:x} r4 s{}", xcoor + UIStyle.margin_x, ycoor + UIStyle.margin_y, UIStyle.hilited_text_color, this.font_size)
                Gdip_TextToGraphics(this.G, sel, opt, UIStyle.font_face, CandidateBoxEx.canvas_width, CandidateBoxEx.canvas_height)
                xcoor += (preW + UIStyle.margin_x * 2)
            }
            if post {
                opt := Format("x{} y{} Left c{:x} r4 s{}", xcoor, ycoor + UIStyle.margin_y, UIStyle.text_color, this.font_size)
                Gdip_TextToGraphics(this.G, post, opt, UIStyle.font_face, CandidateBoxEx.canvas_width, CandidateBoxEx.canvas_height)
            }
            ycoor += preedit_height

            loop num_candidates {
                xcoor := UIStyle.border_width

                local label_color := UIStyle.label_color
                local candidate_text_color := UIStyle.candidate_text_color
                local comment_text_color := UIStyle.comment_text_color
                local back_color := UIStyle.candidate_back_color
                if A_Index == hilited_index {
                    label_color := UIStyle.hilited_label_color
                    candidate_text_color := UIStyle.hilited_candidate_text_color
                    comment_text_color := UIStyle.hilited_comment_text_color
                    back_color := UIStyle.hilited_candidate_back_color
                }

                ; draw candidate back
                pBrush := Gdip_BrushCreateSolid(back_color)
                Gdip_FillRoundedRectangle(this.G, pBrush, xcoor, ycoor, box_width - UIStyle.border_width * 2, candidate_line_height[A_Index], UIStyle.round_corner)
                Gdip_DeleteBrush(pBrush)

                ; label
                local label_text := labels[A_Index]
                opt := Format("x{} y{} Right c{:x} r4 s{}", xcoor + UIStyle.margin_x, ycoor + UIStyle.margin_y, label_color, this.label_font_size)
                Gdip_TextToGraphics(this.G, label_text, opt, UIStyle.label_font_face, CandidateBoxEx.canvas_width, CandidateBoxEx.canvas_height)
                xcoor += max_label_width

                ; candidate
                local candidate := cands[A_Index]
                opt := Format("x{} y{} Left c{:x} r4 s{}", xcoor, ycoor + UIStyle.margin_y, candidate_text_color, this.font_size)
                Gdip_TextToGraphics(this.G, candidate, opt, UIStyle.font_face, CandidateBoxEx.canvas_width, CandidateBoxEx.canvas_height)
                xcoor += max_candidate_width

                ; comment
                if this.has_comment {
                    local comment_text := comments[A_Index]
                    opt := Format("x{} y{} Left c{:x} r4 s{}", xcoor + UIStyle.margin_x, ycoor + UIStyle.margin_y, comment_text_color, this.comment_font_size)
                    Gdip_TextToGraphics(this.G, comment_text, opt, UIStyle.comment_font_face, CandidateBoxEx.canvas_width, CandidateBoxEx.canvas_height)
                }

                ycoor += candidate_line_height[A_Index]
            }

            this.width := box_width
            this.height := box_height
            this.built := true
        }

        Show(x, y) {
            super.Show("NA")
            UpdateLayeredWindow(this.Hwnd, this.hdc, x, y, Ceil(this.width), Ceil(this.height))
        }

        Hide() {
            super.Show("Hide")
        }

        MeasureText(text, options, font, &w := 0, &h := 0) {
            if !this.G
                return false
            local res := Gdip_TextToGraphics(this.G, text, options, font, CandidateBoxEx.canvas_width, CandidateBoxEx.canvas_height, 1)
            if RegExMatch(res, "(.+)\|(.+)\|(.+)\|(.+)\|(.+)\|(.+)", &match) {
                w := Float(match[3])
                h := Float(match[4])
            }
            return !!match
        }
    }

    static BuildPreedit(composition, &pre, &sel, &post) {
        pre := ""
        sel := ""
        post := ""
        if !preedit := composition.preedit
            return false

        static cursor := "‸" ; or 𝙸
        static cursor_size := StrPut(cursor, "UTF-8") - 1 ; do not count null terminator

        local pre_len := StrPut(preedit, "UTF-8")
        local sel_start := composition.sel_start
        local sel_end := composition.sel_end

        local preedit_buffer
        if 0 <= composition.cursor_pos && composition.cursor_pos <= pre_len {
            preedit_buffer := Buffer(pre_len + cursor_size, 0)
            local temp_preedit := Buffer(pre_len, 0)
            StrPut(preedit, temp_preedit, "UTF-8")
            local src := temp_preedit.Ptr
            local tgt := preedit_buffer.Ptr
            Loop composition.cursor_pos {
                byte := NumGet(src, A_Index - 1, "UChar")
                NumPut("UChar", byte, tgt, A_Index - 1)
            }
            src += composition.cursor_pos
            tgt += composition.cursor_pos
            StrPut(cursor, tgt, "UTF-8")
            tgt += cursor_size
            Loop pre_len - composition.cursor_pos {
                byte := NumGet(src, A_Index - 1, "UChar")
                NumPut("UChar", byte, tgt, A_Index - 1)
            }
            pre_len += cursor_size
            if sel_start >= composition.cursor_pos
                sel_start += cursor_size
            if sel_end > composition.cursor_pos
                sel_end += cursor_size
        } else {
            preedit_buffer := Buffer(pre_len, 0)
            StrPut(preedit, preedit_buffer, "UTF-8")
        }

        if 0 <= sel_start && sel_start < sel_end && sel_end <= pre_len {
            pre := StrGet(preedit_buffer, sel_start, "UTF-8")
            sel := StrGet(preedit_buffer.Ptr + sel_start, sel_end - sel_start, "UTF-8")
            post := StrGet(preedit_buffer.Ptr + sel_end, "UTF-8")
            return true
        } else {
            pre := StrGet(preedit_buffer, "UTF-8")
            return false
        }
    }

    static Pt2Px(pt) {
        return pt * A_ScreenDPI / 72
    }
}
