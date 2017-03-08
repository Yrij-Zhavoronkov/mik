unit xterm_gdi;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics;

const maxFrames=8;

type

TXterm_GDI=Object   {***************Graph Terminal via GDI **************}

  type
      TStrLinePtr=^TStrLine;  //указатель на "команду"
      TFramePTR=^TFrame;      //указатель на фрейм
      TRead_state = (query, none);  //состояние терминала ЗАПРОС/ОБЩИЙ

      TStrLine=record
         data:Ansistring;
         next_line:TStrLinePtr;
       end;

      TStrList=record //односвязный список строк
         FirstLine,
         LastLine:TStrLinePtr;
      end;

      TReDrawSquare=record    //инфо о области перерисов. (for opt)
         frame:TFramePTR;
         from_x,from_y:word;
         to_x, to_y:word;
      end;

      //***фреймы
      TFrame=record
         data:TBitmap;
         next_frame:TFramePTR;
         LastStrPtr:TStrLinePtr; //связанный со стрнгом указатель (последний)
      end;

      TFrameList=record  //односвязный список кадров
         DataCount:word;
         FirstFrame,LastFrame:TFramePTR;
         FrameMap:array [0..maxFrames-1] of TFramePTR; //индексы
      end;

      TVirtFrameProp=record
         back_cl,font_cl,cmd_cl:Tcolor;
         v_width,v_height:word;   //в пикселях
      end;


VAR PUBLIC
    readln_proc_lock:TRead_state;  //lock вызовом readln
    Profile_perf:TVirtFrameProp;  //параметры профиля

PRIVATE
    enter_data_layer:TBitmap; //диалог ввода

   //global draw vars
    font_h,font_w,
    x_term_w,x_term_h:byte;
    Frame_Font:TFont;

    //readln_func
    input_value:integer;
    input_buf:string[6];
    input_width:byte;

    //Draw containers
    Frames:TFrameList;
    StringList:TStrList;

    ReDrawInfo:TReDrawSquare;

    //render vars
    last_code:byte;
    draw_y, draw_x:word;

{PROCEDURES}
    procedure xterm_readln;
    procedure xterm_writeln(message:string);
    procedure clean_term(system:boolean);

    {Form GUI}
    procedure OnFormPaint(Sender: TObject);
    procedure OnFormResize(Sender: TObject);

PRIVATE
    procedure ini_DEC;
    procedure DropLines_fromStrList(ptr:TStrLinePtr);
    procedure DropAllFrames;
    procedure create_newFrame;
    function  mask_value(src:string):string;
    procedure inc_drw_y(var cur_draw_y:word; step:byte);
    procedure GDI_Draw_on_Line(work_ptr:TStrLinePtr; UpdDrawInfo:boolean);
    procedure redraw(Draw_at_first:boolean);

    procedure AddData_toStrList(src:string);
    procedure resize_term(x,y:byte; set_win_size:boolean);
    procedure reSet_Font_prop;
    procedure INI_frame(frame:TFramePTR);
    procedure create_DialogFrame;


end;
      {типы и пр..}

      {}

 implementation


 PROCEDURE OnFormPaint(Sender: TObject);
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

end.

