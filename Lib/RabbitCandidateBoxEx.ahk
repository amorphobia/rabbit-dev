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

; https://learn.microsoft.com/windows/win32/winmsg/extended-window-styles
global WS_EX_NOACTIVATE := "+E0x8000000"
global WS_EX_COMPOSITED := "+E0x02000000"
global WS_EX_LAYERED    := "+E0x00080000"

class CandidateBoxEx {
    static dbg := false
    static gui := 0
    static pToken := Gdip_Startup()

    __New(hWnd := 0) {
        this.UpdateUIStyle()
        CandidateBoxEx.hWnd := hWnd
    }

    UpdateUIStyle() {
        CandidateBoxEx.text_color := UIStyle.text_color
        CandidateBoxEx.back_color := UIStyle.back_color
        CandidateBoxEx.candidate_text_color := UIStyle.candidate_text_color
        CandidateBoxEx.candidate_back_color := UIStyle.candidate_back_color
        CandidateBoxEx.label_color := UIStyle.label_color
        CandidateBoxEx.comment_text_color := UIStyle.comment_text_color
        CandidateBoxEx.hilited_text_color := UIStyle.hilited_text_color
        CandidateBoxEx.hilited_back_color := UIStyle.hilited_back_color
        CandidateBoxEx.hilited_candidate_text_color := UIStyle.hilited_candidate_text_color
        CandidateBoxEx.hilited_candidate_back_color := UIStyle.hilited_candidate_back_color
        CandidateBoxEx.hilited_label_color := UIStyle.hilited_label_color
        CandidateBoxEx.hilited_comment_text_color := UIStyle.hilited_comment_text_color

        local hMond := MonitorManage.MonitorFromWindow(CandidateBoxEx.hWnd)
        local info := MonitorManage.GetMonitorInfo(hMond)
        CandidateBoxEx.canvas_width := info.work.right - info.work.left
        CandidateBoxEx.canvas_height := info.work.bottom - info.work.top
    }

    class BoxGui extends Gui {
        built := false
        __New(context, &pre?, &sel?, &post?, &menu?) {
            super.__New(, , this)
            menu := context.menu
            local candidates := menu.candidates
            local num_candidates := menu.num_candidates
            local hilited_index := menu.highlighted_candidate_index + 1
            local composition := context.composition
            CandidateBoxEx.BuildPreedit(composition, &pre, &sel, &post)

            this.Opt(Format("-DPIScale -Caption +Owner +AlwaysOnTop {} {} {}", WS_EX_NOACTIVATE, WS_EX_COMPOSITED, WS_EX_LAYERED))

            if !CandidateBoxEx.pToken {
                if !CandidateBoxEx.pToken := Gdip_Startup()
                    return ; TODO: fallback
            }

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

            pt2px(pt) {
                return pt * A_ScreenDPI / 72
            }
            

            ; preedit
            opt := Format("x0 y0 Left c{:x} r4 s{}", CandidateBoxEx.text_color, pt2px(UIStyle.font_point))
            preM := Gdip_TextToGraphics(this.G, pre, opt, UIStyle.font_face, CandidateBoxEx.canvas_width, CandidateBoxEx.canvas_height, 1)
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
}
