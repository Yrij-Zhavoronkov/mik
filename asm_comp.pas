unit asm_comp;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, SynEdit, SynHighlighterAny, Forms, Controls, Graphics, Dialogs, ExtCtrls, Buttons,
  StdCtrls, Menus, Spin, Grids, types;


 type
  { Tasm_code }

  Tasm_code = class(TForm)
    Bevel1: TBevel;
    force_Clean_mem: TCheckBox;
    GroupBox1: TGroupBox;
    GroupBox2: TGroupBox;
    hide_after: TCheckBox;
    Hide_SG: TSpeedButton;
    Label1: TLabel;
    Label10: TLabel;
    Label11: TLabel;
    Label12: TLabel;
    Label13: TLabel;
    Label14: TLabel;
    Label15: TLabel;
    Label4: TLabel;
    mm_proc: TShape;
    out_status: TLabel;
    open_setup: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    cut: TMenuItem;
    cp: TMenuItem;
    ins: TMenuItem;
    Label5: TLabel;
    Label6: TLabel;
    Label7: TLabel;
    Label8: TLabel;
    Label9: TLabel;
    memory_model: TImage;
    MenuItem4: TMenuItem;
    back: TMenuItem;
    msg_panel: TPanel;
    out_name: TLabel;
    setup_box: TPanel;
    mm_data: TShape;
    mm_cmd: TShape;
    opimize_calls: TCheckBox;
    top_bar: TPanel;
    post: TMenuItem;
    MenuItem7: TMenuItem;
    compile: TMenuItem;
    code_popup: TPopupMenu;
    macros_box: TPanel;
    set_auto_addr: TCheckBox;
    SG_msg: TStringGrid;
    mm_free: TShape;
    Shape3: TShape;
    Shape4: TShape;
    upDate_macro_list: TSpeedButton;
    src_ed: TSynEdit;
    start_val: TSpinEdit;
    States: TImageList;
    log_im: TImageList;
    ASM_style: TSynAnySyn;
    OD: TOpenDialog;
    SD: TSaveDialog;
    MacroGUITable: TStringGrid;
    und_lb: TShape;
    bgd_selector: TShape;
    Vars_later: TRadioButton;
    var_first: TRadioButton;
    procedure Button1Click(Sender: TObject);
    procedure code_popupPopup(Sender: TObject);
    procedure force_Clean_memChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure hide_afterChange(Sender: TObject);
    procedure MacroGUITableDrawCell(Sender: TObject; aCol, aRow: Integer;
      aRect: TRect; aState: TGridDrawState);
    procedure MacroGUITableSelectCell(Sender: TObject; aCol, aRow: Integer;
      var CanSelect: Boolean);
    procedure open_setupClick(Sender: TObject);
    procedure Label5Click(Sender: TObject);
    procedure Label5MouseEnter(Sender: TObject);
    procedure Label5MouseLeave(Sender: TObject);
    procedure Label6Click(Sender: TObject);
    procedure Label7Click(Sender: TObject);
    procedure Label8Click(Sender: TObject);
    procedure cutClick(Sender: TObject);
    procedure cpClick(Sender: TObject);
    procedure insClick(Sender: TObject);
    procedure backClick(Sender: TObject);
    procedure Label9Click(Sender: TObject);
    procedure opimize_callsChange(Sender: TObject);
    procedure postClick(Sender: TObject);
    procedure SB_4Click(Sender: TObject);
    procedure set_auto_addrChange(Sender: TObject);
    procedure SG_msgDrawCell(Sender: TObject; aCol, aRow: Integer;
      aRect: TRect; aState: TGridDrawState);
    procedure SG_msgResize(Sender: TObject);
    procedure Hide_SGClick(Sender: TObject);
    procedure upDate_macro_listClick(Sender: TObject);
    procedure src_edChange(Sender: TObject);
    procedure src_edSpecialLineColors(Sender: TObject; Line: integer;
      var Special: boolean; var FG, BG: TColor);
    procedure start_valChange(Sender: TObject);
    procedure var_firstChange(Sender: TObject);
  private

  public
      var
    error_line:word; //индекс строки, содержащей ошибку (для пользователя)
  end;

var
  asm_code: Tasm_code;

implementation

uses main, mik_asm_compiller, mik_VM, macro;
 {$R *.lfm}

procedure update_mem_model(out_image:TImage);
var
  draw_start:word;
  Data_w,Var_w,proc_w:byte;
  k:real;
begin

 // with out_image.Picture.Bitmap.Canvas do
  with out_image.Canvas do
  begin
     //out_image.Picture.Bitmap.Create;
     clear;
     brush.color:=asm_code.mm_free.Brush.color;
     brush.Style:=bsSolid;
     pen.Style:=psSolid;
     pen.Color:=$cccccc;
     pen.Width:=2;
     rectangle(1,1,width,height);

     data_w:=128;
     proc_w:=64;
     Var_w:=64;
     k:=1;

     draw_start:=asm_code.start_val.Value+1;
     if (draw_start>1) then
     begin
         k:=(width-2-data_w-Var_w-proc_w) / main.RAM_count;
         draw_start:=round(draw_start*k);
         //showmessage(floattostr(k));
     end;

     inc(draw_start,pen.Width);
     pen.Width:=3;

     if (asm_code.var_first.Checked) then
        begin
             brush.Color:=asm_code.mm_data.brush.Color;
             pen.color:=$83694b; //VARS
             RoundRect(draw_start,pen.Width,draw_start+Var_w,height-pen.Width,4,4);
             //rectangle();

             pen.Style:=psClear;
             brush.Color:=asm_code.mm_cmd.brush.Color;
             rectangle(draw_start+Var_w+pen.Width-1,pen.Width,(draw_start+Var_w+data_w),height-pen.Width); //data
             brush.Color:=asm_code.mm_proc.brush.Color;
             rectangle(draw_start+Var_w+data_w-1,pen.Width,(draw_start+Var_w+data_w+proc_w),height-pen.Width); //proc

             pen.color:=$003759;
             pen.Style:=psSolid;
             brush.Style:=bsClear;
             RoundRect(draw_start+Var_w+pen.Width-1,pen.Width,(draw_start+Var_w+data_w+proc_w),height-pen.Width,4,4);
         end
     else
         begin
           pen.color:=$83694b; //VARS
           brush.Color:=asm_code.mm_data.brush.Color;
           RoundRect(draw_start+data_w+pen.Width+proc_w-1,pen.Width,draw_start+Var_w+data_w+proc_w,height-pen.Width,4,4);

           //DATA
           pen.Style:=psClear;
           brush.Color:=asm_code.mm_cmd.brush.Color;
           rectangle(draw_start,pen.Width,(draw_start+data_w),height-pen.Width); //data
           brush.Color:=asm_code.mm_proc.brush.Color;
           rectangle(draw_start+data_w-1,pen.Width,(draw_start+data_w+proc_w),height-pen.Width); //proc

           pen.color:=$003759;
           pen.Style:=psSolid;
           brush.Style:=bsClear;
           RoundRect(draw_start,pen.Width,(draw_start+data_w+proc_w),height-pen.Width,4,4);
         end;
  end;
  out_image.Refresh;
end;

procedure setup_bgd(caller:TLabel; open:boolean);
begin
  if (open) then
    with caller do
    begin
      asm_code.bgd_selector.width:=width+16;
      asm_code.bgd_selector.left:=left-8;
    end;

 //setup label
  if (open)
  then
     begin
        caller.Font.Color:=$0;
        {caller.OnMouseEnter:=nil;
        caller.OnMouseLeave:=nil;}
     end
  else
     begin
       caller.Font.Color:=$9C9C9C;
       {caller.OnMouseEnter:=asm_code.Label5.OnMouseEnter;
       caller.OnMouseLeave:=asm_code.Label5.OnMouseLeave; }
     end;

  asm_code.bgd_selector.visible:=open;
end;

procedure close_dialogs;
begin
  with asm_code do
  begin
    //закрой диалоги, если юзер балуется, то он закончил с ними работу..
    if (macros_box.Visible) then Label9Click(Label9);
    if (setup_box.Visible) then Open_SetupClick(Open_Setup);
  end;
end;



 { Tasm_code }
procedure Tasm_code.FormCreate(Sender: TObject);
begin
  //огр на память
  start_val.MaxValue:=main.RAM_count-32;

  //Загрузка конфига
  with app_config do
  begin
    force_clean_mem.Checked:=clean_mem;
    hide_after.Checked:=hide_win_if_cmp_ok;
    set_auto_addr.Checked:=AutoSet_StartAddr;
    opimize_calls.Checked:=opimized_calls;

    if (vars_firstly) then var_first.Checked:=true
                      else Vars_later.Checked:=true;

    var_first.Checked:=vars_firstly;
    start_val.Value:=addr_shift;
  end;

  //список макросов   530
  with  MacroGUITable do
  begin
       ColWidths[0]:=30;
       ColWidths[1]:=200;
       ColWidths[2]:=298;
  end;

  macros_list.reload_macro_list;

  //settings
  update_mem_model(memory_model);
  ASM_STYLE.Tag:=ASM_STYLE.KeyWords.Count;
end;

procedure Tasm_code.code_popupPopup(Sender: TObject);
begin
  //check code...
  cut.Enabled:=src_ed.SelAvail;
  cp.Enabled:=cut.Enabled;

  ins.Enabled:=src_ed.CanPaste;

  post.Enabled:=src_ed.CanRedo;
  back.Enabled:=src_ed.CanUndo;
end;

procedure Tasm_code.force_Clean_memChange(Sender: TObject);
begin
  app_config.clean_mem:=force_Clean_mem.Checked;
  app_config.MODIFY:=true;
end;

procedure Tasm_code.Button1Click(Sender: TObject);
begin
 // refresh_macro_list;
end;

procedure Tasm_code.FormResize(Sender: TObject);
begin
  if width<656 then width:=656;
  if Height<440 then Height:=440;

  close_dialogs;
end;

procedure Tasm_code.hide_afterChange(Sender: TObject);
begin
  app_config.hide_win_if_cmp_ok:=hide_after.Checked;
  app_config.MODIFY:=true;
end;

procedure Tasm_code.MacroGUITableDrawCell(Sender: TObject; aCol, aRow: Integer;
  aRect: TRect; aState: TGridDrawState);
var
  txt:string;
begin
  if aRow=0 then
    with MacroGUITable do
    begin
         case acol of
              0:txt:='№';
              1:txt:='Имя (формальные пар-ры)' ;
              2:txt:='Статус загрузки';
         end;

    Canvas.Font.Bold:=true;
    canvas.TextOut(aRect.Left+(colWidths[aCol]-canvas.TextWidth(txt)) div 2,aRect.Top+3,txt);
    end;

  if (aCol=0) and (aRow>0) then
    with MacroGUITable do
    begin
     txt:=inttostr(aRow);
     Canvas.Font.Bold:=true;
     canvas.TextOut(aRect.Left+(colWidths[aCol]-canvas.TextWidth(txt)) div 2,aRect.Top+3,txt);
    end;
end;

procedure Tasm_code.MacroGUITableSelectCell(Sender: TObject; aCol,
  aRow: Integer; var CanSelect: Boolean);
begin
  //подгружаем текст:
  out_name.Caption:=MacroGUITable.Cells[1,arow];
  out_status.Caption:=MacroGUITable.Cells[2,arow];
end;

procedure Tasm_code.open_setupClick(Sender: TObject);
var
  new_left:word;
begin
  //close macros
  if (macros_box.Visible) then Label9Click(Label9);

  //вызов бокса
  setup_box.Visible:=not setup_box.Visible;
  setup_bgd(open_setup, setup_box.Visible);

  new_left:=(asm_code.ClientWidth-setup_box.Width) div 2;
  if (new_left>open_setup.left-16) then new_left:=open_setup.left-16;

  setup_box.Left:=new_left;
end;

procedure Tasm_code.Label5Click(Sender: TObject);
begin
  close_dialogs;

   src_ed.Lines.Clear; src_ed.Lines.Add('//ASM - Mik'); src_ed.Modified:=false;
      Asm_code.Caption:='Без имени - Редактор исходного кода';
end;

procedure Tasm_code.Label5MouseEnter(Sender: TObject);
begin
  with sender as TLabel do begin
  //font.Bold:=true;
  if (font.color=$9C9C9C) then font.Color:=clwhite;
  und_lb.Width:=width+8;
  und_lb.Left:=left-4;
  und_lb.Visible:=true;
  end;
end;

procedure Tasm_code.Label5MouseLeave(Sender: TObject);
begin
    with sender as TLabel do begin
    //font.Bold:=false;
    if (font.Color=clWhite) then font.Color:=$9C9C9C;
    und_lb.Visible:=false;
    end;
end;

procedure Tasm_code.Label6Click(Sender: TObject);
begin
  close_dialogs;

  if OD.execute then
begin src_ed.Lines.LoadFromFile(od.FileName); src_ed.Modified:=false;
          Asm_code.Caption:=ExtractFileName(od.FileName)+' - Редактор исходного кода';
          sd.FileName:=od.FileName;
    end;
end;

procedure Tasm_code.Label7Click(Sender: TObject);
begin
  close_dialogs;

    if SD.Execute then begin
  if not (upperCase(extractfileext(sd.FileName))='.MASM')
     then sd.FileName:=sd.FileName+'.masm';

  src_ed.Lines.SaveTOFile(SD.FileName); src_ed.Modified:=false;
 Asm_code.Caption:=ExtractFileName(SD.FileName)+' - Редактор исходного кода';
  end;
end;

procedure Tasm_code.Label8Click(Sender: TObject);
begin
  close_dialogs;

  error_line:=0;
   src_ed.Update;

   if force_Clean_mem.Checked then  clean_mem;  //очистка памяти, если нужно...

   SG_msg.DefaultColWidth:=asm_code.sg_msg.ClientWidth; //очистка + выровнять
   SG_msg.RowCount:=0;

   Compile_ASM;
end;

procedure Tasm_code.cutClick(Sender: TObject);
begin
  src_ed.CutToClipboard;
end;

procedure Tasm_code.cpClick(Sender: TObject);
begin
  src_ed.CopyToClipboard;
end;

procedure Tasm_code.insClick(Sender: TObject);
begin
  src_ed.PasteFromClipboard;
end;

procedure Tasm_code.backClick(Sender: TObject);
begin
src_ed.Undo;
end;

procedure Tasm_code.Label9Click(Sender: TObject);
var
  new_left:word;
begin
  //close setup
  if (setup_box.Visible) then Open_SetupClick(Open_Setup);

  macros_box.Visible:=not macros_box.Visible;
  setup_bgd(Label9, macros_box.Visible);

  new_left:=(asm_code.ClientWidth-macros_box.Width) div 2;
  if (new_left>Label9.left-16) then new_left:=open_setup.left-16;

  macros_box.Left:=new_left;
end;

procedure Tasm_code.opimize_callsChange(Sender: TObject);
begin
  app_config.opimized_calls:=opimize_calls.Checked;
  app_config.MODIFY:=true;
end;

procedure Tasm_code.postClick(Sender: TObject);
begin
  src_ed.Redo;
end;

procedure Tasm_code.SB_4Click(Sender: TObject);
begin
  close;
end;

procedure Tasm_code.set_auto_addrChange(Sender: TObject);
begin
  app_config.AutoSet_StartAddr:=set_auto_addr.Checked;
  app_config.MODIFY:=true;
end;

procedure Tasm_code.SG_msgDrawCell(Sender: TObject; aCol, aRow: Integer;
  aRect: TRect; aState: TGridDrawState);
var
  buf:Tbitmap;
begin
  if (acol=0) then begin
  buf:=Tbitmap.Create;
  log_im.GetBitmap(strtoint(SG_msg.Cells[aCol, aRow][1]),buf);
    SG_msg.Canvas.Draw(arect.left+2,arect.Top, buf);
  end;
end;

procedure Tasm_code.SG_msgResize(Sender: TObject);
begin
  SG_msg.DefaultColWidth:=sg_msg.ClientWidth;
end;

procedure Tasm_code.Hide_SGClick(Sender: TObject);
begin
   sg_msg.Visible:=not sg_msg.Visible;
   if sg_msg.Visible then
   begin
      States.GetBitmap(0,Hide_sg.Glyph);
      msg_panel.Height:=msg_panel.Tag;
   end
   else begin
      States.GetBitmap(1,Hide_sg.Glyph);
      msg_panel.Tag:=msg_panel.Height;
      msg_panel.Height:=Hide_sg.Height;
   end;
end;

procedure Tasm_code.upDate_macro_listClick(Sender: TObject);
begin
   macros_list.reload_macro_list;
  //refresh_macro_list;
end;

procedure Tasm_code.src_edChange(Sender: TObject);
begin
  Label7.Enabled:=true;
  Label5.Enabled:=true;
end;

procedure Tasm_code.src_edSpecialLineColors(Sender: TObject; Line: integer;
  var Special: boolean; var FG, BG: TColor);
begin
   if line=error_line then begin
       special:=true;
       BG:=$50a0ff; // old=6060ff
   end;
end;

procedure Tasm_code.start_valChange(Sender: TObject);
begin
  app_config.addr_shift:=start_val.Value;

  update_mem_model(memory_model);
  app_config.MODIFY:=true;
end;

procedure Tasm_code.var_firstChange(Sender: TObject);
begin
  //set cfg
  app_config.vars_firstly:=var_first.Checked;
  app_config.MODIFY:=true;
  update_mem_model(memory_model);
end;

end.

