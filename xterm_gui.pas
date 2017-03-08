unit xterm_gui;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs, Menus,
  StdCtrls, ExtCtrls, LCLType, Buttons, types, LMessages;

type

  { Tterm }

  Tterm = class(TForm)
    MainMenu1: TMainMenu;
    MenuItem1: TMenuItem;
    MenuItem10: TMenuItem;
    MenuItem11: TMenuItem;
    MenuItem12: TMenuItem;
    MenuItem13: TMenuItem;
    MenuItem14: TMenuItem;
    MenuItem15: TMenuItem;
    MenuItem16: TMenuItem;
    MenuItem17: TMenuItem;
    size0: TMenuItem;
    size1: TMenuItem;
    size2: TMenuItem;
    size3: TMenuItem;
    theme0: TMenuItem;
    theme1: TMenuItem;
    theme3: TMenuItem;
    MenuItem2: TMenuItem;
    theme2: TMenuItem;
    MenuItem21: TMenuItem;
    MenuItem22: TMenuItem;
    kind_line: TMenuItem;
    kind_tree: TMenuItem;
    MenuItem3: TMenuItem;
    MenuItem4: TMenuItem;
    MenuItem5: TMenuItem;
    MenuItem6: TMenuItem;
    MenuItem7: TMenuItem;
    MenuItem8: TMenuItem;
    MenuItem9: TMenuItem;
    Scroll: TScrollBar;
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormKeyPress(Sender: TObject; var Key: char);
    procedure FormMouseWheelDown(Sender: TObject; Shift: TShiftState;
      MousePos: TPoint; var Handled: Boolean);
    procedure FormMouseWheelUp(Sender: TObject; Shift: TShiftState;
      MousePos: TPoint; var Handled: Boolean);
    procedure FormPaint(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure MenuItem11Click(Sender: TObject);
    procedure MSDOs(Sender: TObject);
    procedure size0Click(Sender: TObject);
    procedure theme0Click(Sender: TObject);
    procedure MenuItem3Click(Sender: TObject);
    procedure MenuItem4Click(Sender: TObject);
    procedure MenuItem9Click(Sender: TObject);
    procedure ScrollScroll(Sender: TObject; ScrollCode: TScrollCode;
      var ScrollPos: Integer);
    procedure OptiRepaint;
  private
    procedure RedrawOnThemeChange;
    end;

var
  term: Tterm;

implementation

uses mik_VM, xterm_core, main;

{$R *.lfm}

{ Tterm }

procedure Tterm.FormCreate(Sender: TObject);
begin
  enter_data_layer:=Tbitmap.Create;

  {default values}
  Frame_Font:=TFont.Create;
  Frame_Font.Name:='Droid Sans Mono';
  Frame_Font.size:=9;

  readln_proc_lock:=none;

   //sync conf
  with main.app_config do
  begin
     //set size
    case TERM_W_size of
         1:size1.Click;
         2:size2.Click;
         3:size3.Click
    else size0.Click; //default
    end;

    case TERM_theme of  //внимание вызывает перерисовку!!!!
         0:theme0.Click;
         1:theme1.Click;
         3:theme3.Click
    else theme2.Click; //default
    end;
   MODIFY:=false;
  end;
end;

procedure Tterm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  if (MikCpu<>nil) then
     main_gui.stop_execClick(nil);

     main_gui.save_config;
end;

procedure Tterm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  IF ((MikCpu<>nil) and (KEY=VK_C) and (Shift=[ssCtrl])) then begin
    //Ctrl+C - kill terminal
    xterm_writeln('---------------------------');
    xterm_writeln('[!!] Ctrl + C; Выполение остановлено.');
    main_gui.stop_execClick(nil);
  end

  ELSE

  if readln_proc_lock=query then
    if (key=VK_RETURN) and (shift=[]) then
        if tryStrToint(input_buf,input_value) then
           if (input_value>=-32768) and (input_value <=32767) then
           begin
            //пишем, что ввели то-то и предаем управление далее
            readln_proc_lock:=none;
            //lines.Add('<'+inttostr(input_value));  //защита от -1)        DEPRECATED
            AddData_toStrList('<'+inttostr(input_value));
            input_buf:='';
            scroll.Enabled:=true;

            redraw(false); //new
            Repaint;       //full only

            ////передаем управление далее (возобновляем поток)
            main_gui.Enabled:=true;
            MikCpu.Resume;
           end;
end;

procedure Tterm.FormKeyPress(Sender: TObject; var Key: char);
var
 dr_x,dr_y:word;
begin
  if readln_proc_lock=query then begin
  if input_buf='' then begin
  if not (key in ['-','0'..'9']) then key:=#0;
  end
  else if not (key in ['0'..'9',#8]) then key:=#0;

  if key<>#0 then
       case key of
       #8:delete(input_buf,length(input_buf),1)
       else input_buf:=input_buf+key;
       end;

  dr_x:=(enter_data_layer.Width-6 - input_width) div 2;
  dr_y:=font_h*4-2;

  //отрис буфер
  enter_data_layer.Canvas.Font.Color:=Profile_perf.Back_cl;
  enter_data_layer.Canvas.TextOut(dr_x,dr_y,'0000-32768');
  enter_data_layer.Canvas.Font.Color:=Profile_perf.font_cl;
  enter_data_layer.Canvas.TextOut(dr_x+input_width-enter_data_layer.Canvas.TextWidth(input_buf),dr_y,input_buf);
  Repaint; //Fill only
end;
end;

procedure Tterm.FormMouseWheelDown(Sender: TObject; Shift: TShiftState;
  MousePos: TPoint; var Handled: Boolean);
begin
scroll.Position:=scroll.Position+6;
end;

procedure Tterm.FormMouseWheelUp(Sender: TObject; Shift: TShiftState;
  MousePos: TPoint; var Handled: Boolean);
begin
scroll.Position:=scroll.Position-6;
end;


procedure Tterm.OptiRepaint; //внутреннй вызов
var
  dr_y_shift:word;
    frame_id:byte;
begin
   frame_id:=scroll.position div Profile_perf.v_height;
   dr_y_shift:=scroll.position mod Profile_perf.v_height;

 with ReDrawInfo do
   if (frame=nil) or (need_to_cln_canvas)
      then
      begin
           REPAINT; {область обновления НЕ ЗАДАНА, рисуем все. --> sys.redraw }
           need_to_cln_canvas:=false;
      end
      ELSE
        if (frames.FrameMap[frame_id]=frame) then
           term.canvas.CopyRect(RECT(from_x,from_y+dr_y_shift,to_x,to_y+dr_y_shift), frame^.data.Canvas, RECT(from_x,from_y,to_x,to_y));
end;

procedure Tterm.FormPaint(Sender: TObject);
var
  dr_y_shift:word;
  frame_id:byte;
begin
 //full repaint
  frame_id:=scroll.position div Profile_perf.v_height;
  dr_y_shift:=scroll.position mod Profile_perf.v_height;

  Canvas.Draw(0,-dr_y_shift, frames.FrameMap[frame_id]^.data);

    //отрисовали все? если был сдвиг то нет  + если существует след кадр
    if (dr_y_shift>0) and (frame_id<Frames.DataCount) then
       begin
          inc(frame_id);
          Canvas.Draw(0,(Profile_perf.v_height-dr_y_shift),frames.FrameMap[frame_id]^.data);
       end;


   //отрисовка диалога запроса значения)
  if (readln_proc_lock=QUERY) then
    canvas.Draw((term.ClientWidth-enter_data_layer.Width) div 2,(term.ClientHeight - enter_data_layer.Height) div 2,enter_data_layer);
end;


procedure Tterm.FormResize(Sender: TObject);
{const
  min_w=80;
  min_h=24;

  max_w=255;
  max_h=255;
var
    new_w,new_h:word;  }
begin
 {  В Win* живет своей жизнью режим bsSizable для формы
    по этому стоит bsSingle, который запрещает измененеие размера пользователем
    => данный код бесполезен (пока вкл bsSingle)


 //расчет изменений....
   new_w:=clientWidth div font_w;
   new_h:=clientHeight div font_h;

  if (new_w<min_w) then new_w:=min_w
              else
  if (new_w>max_w) then new_w:=max_w;

  if (new_h<min_h) then new_h:=min_h
              else
  if (new_h>max_h) then new_h:=max_h;

  //перерисовка только если изменился размер...
  resize_term(new_w,new_h,((x_term_w<>new_w) or (x_term_h<>new_h)) );
}
end;

procedure Tterm.MenuItem11Click(Sender: TObject);
begin
 clean_term(false);
end;

procedure Tterm.MSDOs(Sender: TObject);
begin
 with sender as TMenuitem do
 app_config.TERM_W_theme:=tag;
 RedrawOnThemeChange;
end;

procedure Tterm.size0Click(Sender: TObject);
begin
 with sender as TMenuItem do
 app_config.TERM_W_size:=tag;

      case app_config.TERM_W_size of
         1:resize_term(80,44,true);
         2:resize_term(132,24,true);
         3:resize_term(132,44,true)
      else
         resize_term(80,24,true);  //default
      end;

  app_config.MODIFY:=true;
end;

procedure Tterm.RedrawOnThemeChange;   //просто тот кусок повторялся n раз))
var
 key:char;
begin
  color:=Profile_perf.back_cl;  //цвет формы

   //пересоздай кно диалога под новую тему
   create_DialogFrame;

  //перерисовка.....
 redraw(true);
  if readln_proc_lock=query then
     begin xterm_readln; key:=#0; term.KeyPress(key); end  //в этом случае и так  перерисует
     else  Repaint;
end;

procedure Tterm.theme0Click(Sender: TObject);
begin
   with sender as TMenuItem do
   app_config.TERM_theme:=tag;

   case app_config.TERM_theme of
        0:begin
             Profile_perf.font_cl:=clLime;
             Profile_perf.back_cl:=$0;
             Profile_perf.cmd_cl:=$342ebe;
          end;
        1:begin
             Profile_perf.font_cl:=clWhite;
             Profile_perf.back_cl:=$0;
             Profile_perf.cmd_cl:=$43fbf9
          end;
        3:begin
             Profile_perf.font_cl:=$0;
             Profile_perf.back_cl:=clWhite;
             Profile_perf.cmd_cl:=$d02c37;
          end

        else
           begin  {DEFAULT}
                Profile_perf.font_cl:=$0;
                Profile_perf.back_cl:=$DDFFFF;
                Profile_perf.cmd_cl:=$d02c37;
           end;
     end;

  RedrawOnThemeChange;
  app_config.MODIFY:=true;
end;

procedure Tterm.MenuItem3Click(Sender: TObject);
var
 key:char;
begin
 MenuItem4.Enabled:=true;
 if Frame_Font.Size<14 then begin
 Frame_Font.Size:=Frame_Font.Size+1;
 resize_term(x_term_w,x_term_h,true);
end;
 if Frame_Font.Size=14 then MenuItem3.Enabled:=false;

 reSet_Font_prop;
 create_DialogFrame;
if readln_proc_lock=query then begin key:=#0; term.KeyPress(key); end;
end;

procedure Tterm.MenuItem4Click(Sender: TObject);
var
 key:char;
begin
 MenuItem3.Enabled:=true;
 if Frame_Font.Size>7 then begin
 Frame_Font.Size:=Frame_Font.Size-1;
 resize_term(x_term_w,x_term_h,true);
 end;

 if Frame_Font.Size=7 then MenuItem4.Enabled:=false;

 reSet_Font_prop;
 create_DialogFrame;
 if readln_proc_lock=query then begin key:=#0; term.KeyPress(key); end;
end;

procedure Tterm.MenuItem9Click(Sender: TObject);
begin
  close;
end;

procedure Tterm.ScrollScroll(Sender: TObject; ScrollCode: TScrollCode;
  var ScrollPos: Integer);
begin
  Repaint; //full only!
end;

end.

