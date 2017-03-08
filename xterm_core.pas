unit xterm_core;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Controls, xterm_gui;

const maxFrames=8;

type
  TStrLinePtr=^TStrLine;
  TFramePTR=^TFrame;
  TRead_state = (query, none);

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


 var
    //lock вызовом readln
    readln_proc_lock:TRead_state;

   //параметры профиля
    Profile_perf:TVirtFrameProp;

    //диалог ввода
    enter_data_layer:TBitmap;

   //global draw vars
    font_h,font_w,
    x_term_w,x_term_h:byte;
    Frame_Font:TFont;

    //readln_func
    input_value:integer; //????
    input_buf:string[6];
    input_width:byte;

    //Draw containers
    Frames:TFrameList;
    StringList:TStrList;

    need_to_cln_canvas:boolean;

    ReDrawInfo:TReDrawSquare;



{PROC HEADRS}
  procedure xterm_readln;
  procedure xterm_writeln(message:string);
  procedure clean_term(system:boolean);
  procedure redraw(Draw_at_first:boolean);

  function mask_value(src:string):string;
  procedure AddData_toStrList(src:string);
  procedure resize_term(x,y:byte; set_win_size:boolean);
  procedure reSet_Font_prop;
  procedure INI_frame(frame:TFramePTR);
  procedure create_DialogFrame;

implementation
uses main;

var
    //render vars
    last_code:byte;
    draw_y, draw_x:word;

    {DEC PROC}

procedure ini_DEC; //ok
begin
   //stringlist
   StringList.LastLine:=nil;
   StringList.FirstLine:=nil;

   //frame
   Frames.DataCount:=0;
   Frames.FirstFrame:=nil;
   Frames.LastFrame:=nil;

   need_to_cln_canvas:=false;
end;

{EXPEREMENTAL}

procedure DropLines_fromStrList(ptr:TStrLinePtr); //убить элементы до указателя  ok
var
    tmp_ptr:TStrLinePtr;
begin
  //удаляем все с start до указателя
  with StringList do
       while (FirstLine<>nil) and (FirstLine<>ptr) do
       begin
         tmp_ptr:=FirstLine;
         FirstLine:=FirstLine^.next_line;
         dispose(tmp_ptr);
       end;

  //если удалили все до конца....
  if (StringList.FirstLine=nil) then StringList.LastLine:=nil;
end;

procedure DropAllFrames;         //ok
var
 tmp_ptr:TFramePTR;
begin
 with frames do
         WHILE (FirstFrame<>nil) do
         begin
            tmp_ptr:=FirstFrame;
            freeAndNil(FirstFrame^.data);
            FirstFrame^.LastStrPtr:=nil;

            FirstFrame:=Tmp_ptr^.next_frame;

            Tmp_ptr^.next_frame:=nil;
            dispose(tmp_ptr);
         end;

     Frames.DataCount:=0;
     Frames.LastFrame:=nil;
end;

procedure AddData_toStrList(src:string); //создать новый элемет связного списка  ok
var
    new_ptr:TStrLinePtr;
begin
    new(new_ptr);
    new_ptr^.data:=src;
    new_ptr^.next_line:=nil;

    {линковка}
    if (StringList.FirstLine=nil) then StringList.FirstLine:=new_ptr;
       if not (StringList.LastLine=nil) then StringList.LastLine^.next_line:=new_ptr;

    StringList.LastLine:=new_ptr;
end;

procedure create_newFrame;     //ok
var
    temp_ptr:TFramePTR;
    ind:byte;
begin
   //запрос на новую ячейку?
   //если переполнение, то "забываем" 1 кадр и все строки с ним связанные
with frames do
  if (Frames.DataCount=maxFrames) then
     begin
        //удалим стринги, связанные с фреймом
        DropLines_fromStrList(Frames.FirstFrame^.LastStrPtr);

        {перелинкуем первый в конец}
        LastFrame^.next_frame:=FirstFrame;
        LastFrame:=FirstFrame;

        FirstFrame:=LastFrame^.next_frame;
        LastFrame^.next_frame:=nil;
     end
  else  //иначе создаем новый элемент списка!
    begin
      new(temp_ptr);
      temp_ptr^.next_frame:=nil;
      temp_ptr^.LastStrPtr:=nil;

      {линковка}
      if (frames.FirstFrame=nil) then frames.FirstFrame:=temp_ptr
                                 else frames.LastFrame^.next_Frame:=temp_ptr;

      frames.LastFrame:=temp_ptr;

      {первичная инициализация - создание bitmap}
      with temp_ptr^ do
         begin
             data:=TBitmap.Create;
             data.PixelFormat:=pf16bit;

             data.Canvas.Font:=Frame_Font;
             data.Canvas.Brush.Color:=Profile_perf.back_cl;
             data.Canvas.pen.Color:=Profile_perf.font_cl;
             data.Canvas.Font.Color:=Profile_perf.font_cl;

             data.SetSize(Profile_perf.v_width, Profile_perf.v_height);   //pixels
          end;
      //не забудь счетчик....
      inc(frames.DataCount);
    end;

    //пост инициализация (настройка)
    INI_frame(frames.LastFrame);

    {индексация}
    temp_ptr:=frames.firstFrame;
    ind:=0;
    while not (temp_ptr=nil) do
      begin
          frames.FrameMap[ind]:=temp_ptr;
          temp_ptr:=temp_ptr^.next_frame;
          inc(ind);
      end;
end;

procedure INI_frame(frame:TFramePTR);    //ок
var
    nw,nh:word;
    w,h:word;
    dh,dw:word; //дельта H и W
    shift_l,shift_t:word;
begin
   need_to_cln_canvas:=true;

   //setup size
   frame^.data.SetSize(Profile_perf.v_width, Profile_perf.v_height);
   //set fonts
   frame^.data.Canvas.Font:=Frame_Font;
   frame^.data.canvas.Font.Color:=profile_perf.font_cl;
   frame^.data.canvas.pen.color:=profile_perf.font_cl;
   frame^.data.canvas.brush.color:=profile_perf.back_cl;
   frame^.data.canvas.Brush.Style:=bsSolid;

   frame^.data.Canvas.Rectangle(-1,-1,Profile_perf.v_width+1,Profile_perf.v_height+1);

  { //draw symbolic
   w:=term.symb.Picture.Width;
   h:=term.symb.Picture.Height;
   nw:=round(Profile_perf.v_width*0.85);
   dw:=w-nw;

   dh:=round(h*dw/w);
   nh:=h-dh;

   shift_l:=(Profile_perf.v_width-nw) div 2;
   shift_t:=(Profile_perf.v_height-nh) div 2;

   frame^.data.Canvas.StretchDraw(rect(shift_l,shift_t,shift_l+nw,shift_t+nh),term.symb.Picture.Bitmap); }
end;

{END EXP}

{BASE PROC}

procedure reSet_Font_prop;
begin
  enter_data_layer.Canvas.Font:=Frame_Font;

  font_w:=enter_data_layer.canvas.TextWidth('A');  //получить ширину символа
  font_h:=enter_data_layer.canvas.TextHeight('A'); //высоту символа
end;

function  mask_value(src:string):string;
begin
   while length(src)<6 do src:=' '+src;
   mask_value:=src+' ';
end;

procedure resize_term(x,y:byte; set_win_size:boolean); //ПЕРЕСМОТР (мб вызывать и на пустую)
begin
 with term do begin
  x_term_w:=x; x_term_h:=y; //by lines/rows!!! not pixels!!

  reSet_Font_prop;

  //clean FRAMES
  DropAllFrames;

  Profile_perf.v_width:=x_term_w*font_w;
  Profile_perf.v_height:=x_term_h*font_h;

  if set_win_size then
    begin
      //hack  disallow resize event
      OnResize:=nil;
      clientWidth:=Profile_perf.v_width;
      clientHeight:=Profile_perf.v_height;

      //allow resize event
      OnResize:=@FormResize;
    end;


 redraw(true);
 Repaint; //fillRepaint!
 end;
end;

procedure clean_term(system:boolean); //ok
begin
 with term do begin
  if system then
  need_to_cln_canvas:=false;
  readln_proc_lock:=none;

  //destrioy all frames
  DropAllFrames;
   //Destroy ALL stringlist
  DropLines_fromStrList(nil);

  redraw(true);
  repaint;  //fill!!
 end;
end;

procedure inc_drw_y(var draw_y:word; step:byte); //ok
var
    NewMax:integer;
begin
  //увеличиваем счетчик
  inc(draw_y,step*font_h);
  NewMax:=0;

  //нам еще фрейм?...
  if draw_y>=Profile_perf.v_height then
     begin
       //наращиваем суммарный объем страниц
       //term.scroll.Max:=(term.scroll.Max+step*font_h);  //testing

        {//пишем указатель последненго стринга.. }
        frames.LastFrame^.LastStrPtr:=stringList.LastLine;
        create_newFrame;
        draw_y:=1;
     end;

  //UPD SCROLL  (exp)
  if (frames.DataCount>1) then
     NewMax:=(frames.DataCount-1)*Profile_perf.v_height;//+draw_y;

  //update or not?
  if (NewMax>term.Scroll.Max) then term.Scroll.Max:=NewMax;
end;

procedure GDI_Draw_on_Line(work_ptr:TStrLinePtr; UpdDrawInfo:boolean); //EXPEREMENTAL  >> frame pointer   ok
var
  code:byte;
  back_x,back_y:word;
BEGIN
 with frames do
   while not (work_ptr=nil) do
   begin
       LastFrame^.data.Canvas.Brush.Style:=bsClear;  //////////////////////FIХ!
       //up info

       if (UpdDrawInfo) then ReDrawInfo.frame:=LastFrame
                        else ReDrawInfo.frame:=nil;

      case work_ptr^.data[1] of
           '>':code:=1;
           '<':code:=2
           else code:=0;
         end;

      if code=0 then //обычный текст....
         begin
          if last_code<>0 then inc_drw_y(draw_y,1);

              draw_x:=1;
              LastFrame^.data.Canvas.TextOut(draw_x,draw_y,work_ptr^.data);

              {**reserve data**}
                back_x:=draw_x;
                back_y:=draw_y;
              {end}

              inc_drw_y(draw_y,1);
              last_code:=code;
         end;

      if code=1 then  //формат вывод
         begin
              //инициализация
             if last_code=2 then begin draw_x:=1; inc_drw_y(draw_y,2);  end;

             if draw_x+7*font_w>=Profile_perf.v_width then
                 begin
                      if last_code=1 then draw_x:=7*font_w+1 else draw_x:=1; inc_drw_y(draw_y,1);
                 end; //reset

             {**reserve data**}
                back_x:=draw_x;
                back_y:=draw_y;
             {end}

             if last_code=1 then LastFrame^.data.Canvas.TextOut(draw_x,draw_y,mask_value(copy(work_ptr^.data,2,10)))
             else
             begin
                  LastFrame^.data.Canvas.Font.Bold:=true;
                  LastFrame^.data.Canvas.Font.Color:=Profile_perf.cmd_cl;
                  LastFrame^.data.Canvas.TextOut(draw_x,draw_y,'Вывод: ');
             inc(draw_x,7*font_w );
                  LastFrame^.data.Canvas.Font.Bold:=false;
                  LastFrame^.data.Canvas.Font.Color:=Profile_perf.font_cl;
                  LastFrame^.data.Canvas.TextOut(draw_x,draw_y,mask_value(copy(work_ptr^.data,2,10)));
             end;

             inc(draw_x,7*font_w );
             last_code:=code;
         end;

      if code=2 then //формат ввод
         begin
              //инициализация
             if last_code=1 then begin draw_x:=1; inc_drw_y(draw_y,2);  end;

             if draw_x+7*font_w>=Profile_perf.v_width then
                 begin
                      if last_code=2 then draw_x:=7*font_w+1 else draw_x:=1; inc_drw_y(draw_y,1);
                 end; //reset

             {**reserve data**}
                back_x:=draw_x;
                back_y:=draw_y;
             {end}

             if last_code=2 then LastFrame^.data.Canvas.TextOut(draw_x,draw_y,mask_value(copy(work_ptr^.data,2,10)))
             else begin
                  LastFrame^.data.Canvas.Font.Bold:=true;
                  LastFrame^.data.Canvas.Font.Color:=Profile_perf.cmd_cl;
                  LastFrame^.data.Canvas.TextOut(draw_x,draw_y,'Ввод:  ');
             inc(draw_x,7*font_w );
                  LastFrame^.data.Canvas.Font.Bold:=false;
                  LastFrame^.data.Canvas.Font.Color:=Profile_perf.font_cl;
                  LastFrame^.data.Canvas.TextOut(draw_x,draw_y,mask_value(copy(work_ptr^.data,2,10)));
             end;

             inc(draw_x,7*font_w );
             last_code:=code;
         end;
      //inc(index);  DEPRECATED


   {finalize update RDInfo}
   if (UpdDrawInfo) then
        with ReDrawInfo do
        begin
            from_x:=back_x;
            from_y:=back_y;

            case code of
                 0:
                   begin
                      to_x:=from_x+Frame^.data.Canvas.TextWidth(work_ptr^.data);
                      to_y:=draw_y;
                   end;
                 1..2:
                   begin
                      to_x:=draw_x;
                      to_y:=from_y+font_h;
                   end;
            end;
        end;

       work_ptr:=work_ptr^.next_line;
   end;
end;

{procedure GDI_Draw_on_TREE(work_ptr:TStrLinePtr); //DEPRECATED >> frame pointer
var
  code:byte;
  x_in,x_out,line_ln,line_step,tree_shift:byte;
BEGIN
 with frames do
 begin
     x_in:=4*font_w;
     x_out:=24*font_w;
     line_ln:=4*font_w;
     line_step:=font_h div 2;
     tree_shift:=3*font_w;


        while not (work_ptr=nil) do
        begin

           {INPUT:          OUTPUT:
              |___4            |____5
              |___4            |____5
              |___4            |____5
              |___4            |____5
              |___4            |____5}

             case work_ptr^.data[1] of
                '>':code:=1; //out
                '<':code:=2  //inp
                else code:=0;
              end;

           if code=0 then //обычный текст....
              begin
               if last_code<>0 then
                  begin
                       draw_x:=1;
                       if draw_y<inp_draw_y then draw_y:=inp_draw_y;
                       inc_drw_y(draw_y,1);
                  end;
                   LastFrame^.data.Canvas.TextOut(draw_x,draw_y,work_ptr^.data);
                   draw_x:=1;
                   inc_drw_y(draw_y,1);
                   last_code:=code;
              end;

           if code=1 then  //формат вывод
              begin
                   //инициализация
                  if (last_code=0) or (draw_y=1) then
                     begin
                       LastFrame^.data.Canvas.Font.Bold:=true;
                       LastFrame^.data.Canvas.Font.Color:=Profile_perf.cmd_cl;
                       LastFrame^.data.Canvas.TextOut(x_out,draw_y,'Вывод:');
                       inc_drw_y(draw_y,1);
                     end;

                       //отрисовка дерева
                       LastFrame^.data.Canvas.Line(x_out+tree_shift,draw_y+line_step,x_out+Line_ln+tree_shift,draw_y+line_step); //x
                       if LastFrame^.data.Canvas.Font.Bold
                          then
                              LastFrame^.data.Canvas.Line(x_out+tree_shift,draw_y,x_out+tree_shift,draw_y+line_step) //y
                          else
                              LastFrame^.data.Canvas.Line(x_out+tree_shift,draw_y-line_step,x_out+tree_shift,draw_y+line_step); //y

                       //отрис значение
                       LastFrame^.data.Canvas.Font.Bold:=false;
                       LastFrame^.data.Canvas.Font.Color:=Profile_perf.font_cl;
                       LastFrame^.data.Canvas.TextOut(x_out+tree_shift+Line_ln,draw_y,mask_value(copy(work_ptr^.data,2,10)));

                       inc_drw_y(draw_y,1);
                       last_code:=code;
              end;

           if code=2 then //формат ввод
              begin
                   //инициализация
                  if last_code=0 then inp_draw_y:=draw_y;

                  if (last_code=0) or (inp_draw_y=1) then
                     begin
                       LastFrame^.data.Canvas.Font.Bold:=true;
                       LastFrame^.data.Canvas.Font.Color:=Profile_perf.cmd_cl;
                       LastFrame^.data.Canvas.TextOut(x_in,Inp_draw_y,'Ввод: ');
                       inc_drw_y(Inp_draw_y,1);
                     end;

                         //отрисовка дерева
                       LastFrame^.data.Canvas.Line(x_in+tree_shift,inp_draw_y+line_step,x_in+Line_ln+tree_shift,inp_draw_y+line_step); //x
                       if LastFrame^.data.Canvas.Font.Bold
                          then
                              LastFrame^.data.Canvas.Line(x_in+tree_shift,inp_draw_y,x_in+tree_shift,inp_draw_y+line_step) //y
                          else
                              LastFrame^.data.Canvas.Line(x_in+tree_shift,inp_draw_y-line_step,x_in+tree_shift,inp_draw_y+line_step); //y

                       //отрис значение
                       LastFrame^.data.Canvas.Font.Bold:=false;
                       LastFrame^.data.Canvas.Font.Color:=Profile_perf.font_cl;
                       LastFrame^.data.Canvas.TextOut(x_in+tree_shift+Line_ln,inp_draw_y,mask_value(copy(work_ptr^.data,2,10)));

                       inc_drw_y(inp_draw_y,1);
                       last_code:=code;
              end;
           //inc(index); DEPRECATED
           work_ptr:=work_ptr^.next_line;
        end;
        end;
  {END TREE}
END; }

procedure redraw(Draw_at_first:boolean);  //ПЕРЕСМОТР
var
  wrk_ptr:TStrLinePtr;
begin
    //кидаем указатель лист строк в хвост
    wrk_ptr:=StringList.LastLine;

    //инициализация при полной перерисовке
    if Draw_at_first then
    begin
     //чистим фреймы
     DropAllFrames;

     Profile_perf.v_width:=x_term_w*font_w;
     Profile_perf.v_height:=font_h*x_term_h;

     create_newFrame;

     draw_y:=1;
     draw_x:=1;

     last_code:=0;

     //SCROLL ini
     term.scroll.Max:=0;
     term.Scroll.PageSize:=6; //двиг на 6 px

     wrk_ptr:=StringList.FirstLine;
    end;

    GDI_Draw_on_Line(wrk_ptr,not Draw_at_first);
   end;

procedure create_DialogFrame;
var
 t_w:word;
 lines_ct,shadow_size:byte;
 inp_x:byte;

 out_str:string;
begin
  lines_ct:=6;
  out_str:='   Введите значение в интервале [-32768..32767]:   ';
  shadow_size:=6;
  t_w:= enter_data_layer.canvas.TextWidth(' '+out_str+' ');
  //t_h is DEPRECATED


  with enter_data_layer do
  begin
       //setup size  + shadow..
       Width:=t_w+shadow_size;
       Height:=font_h*lines_ct+shadow_size;

       //setup colors && fonts
       Canvas.Pen.Style:=psClear;
       Canvas.Brush.Color:=Profile_perf.back_cl;
       Canvas.font:=Frame_Font;

       //clean
       Canvas.Rectangle(-1,-1, Width+1, Height+1);
       //shadow
       Canvas.Brush.Color:=$444444;
       Canvas.Rectangle(shadow_size,shadow_size,shadow_size+t_w,shadow_size+font_h*lines_ct);


       case app_config.TERM_W_theme of
            0:begin
                  {тема DOS}
                  //window's decorations
                 Canvas.Pen.Style:=psSolid;
                 Canvas.Pen.Color:=Profile_perf.cmd_cl;
                 //borders
                 Canvas.Brush.Color:=Profile_perf.cmd_cl;
                 Canvas.Rectangle(0,0,t_w,font_h*lines_ct);
                 Canvas.Brush.Style:=bsClear;

                 Canvas.Pen.Color:=Profile_perf.back_cl;
                 Canvas.Rectangle(shadow_size,shadow_size,t_w-shadow_size,font_h*lines_ct-shadow_size);
                 Canvas.font.Color:=Profile_perf.back_cl;

                  Canvas.TextOut(4,font_h * 2 ,out_str);

                  out_str:='  Ввод данных  ';
                  canvas.Font.Bold:=true;
                   Canvas.Brush.Style:=bsSolid;
                  Canvas.TextOut((t_w-canvas.TextWidth(out_str)) div 2,2,out_str);
                  canvas.Font.Bold:=false;
              end;
            1:begin  {тема win95  - black}
                 //window's decorations
                 Canvas.Pen.Style:=psSolid;
                 Canvas.Pen.Color:=Profile_perf.font_cl;
                 //borders
                 Canvas.Brush.Color:=Profile_perf.back_cl;
                 Canvas.Rectangle(0,0,t_w+2,font_h*lines_ct+2);
                 Canvas.Brush.Style:=bsClear;

                Canvas.Pen.Color:=Profile_perf.font_cl;
                Canvas.Pen.Width:=3;
                Canvas.Rectangle(2,2,t_w,font_h*lines_ct);
                Canvas.Brush.Style:=bsSolid;


                //widows's text
                Canvas.font.Color:=Profile_perf.cmd_cl;
                Canvas.TextOut(4,font_h * 2 ,out_str);

                //title
                canvas.Brush.color:=Profile_perf.font_cl;
                Canvas.Pen.Width:=1;
                canvas.Rectangle(5,5,t_w-3,font_h+8);

                out_str:='Ввод данных';
                Canvas.font.Color:=Profile_perf.back_cl;
                canvas.Font.Bold:=true;
                Canvas.TextOut((t_w-canvas.TextWidth(out_str)) div 2,6,out_str);

                Canvas.font.Color:=clSilver;
                Canvas.TextOut(t_w-font_h*2-3,5,'_');
                Canvas.TextOut(t_w-font_h-3,7,'х');
                canvas.Font.Bold:=false;
              end;


            2:begin  {тема win98}
                 //window's decorations
                 Canvas.Pen.Style:=psSolid;
                 Canvas.Pen.Color:=Profile_perf.font_cl;
                 //borders
                 Canvas.Brush.Color:=Profile_perf.back_cl;
                 Canvas.Rectangle(0,0,t_w+2,font_h*lines_ct+2);
                 Canvas.Brush.Style:=bsClear;


                Canvas.Pen.Color:=Profile_perf.cmd_cl;
                Canvas.Pen.Width:=3;
                Canvas.Rectangle(2,2,t_w,font_h*lines_ct);
                Canvas.Brush.Style:=bsSolid;


                //widows's text
                Canvas.font.Color:=Profile_perf.font_cl;
                Canvas.TextOut(4,font_h * 2 ,out_str);

                //title
                canvas.Brush.color:=Profile_perf.cmd_cl;
                Canvas.Pen.Width:=1;
                canvas.Rectangle(5,5,t_w-3,font_h+8);

                out_str:='Ввод данных';
                Canvas.font.Color:=Profile_perf.back_cl;
                canvas.Font.Bold:=true;
                Canvas.TextOut((t_w-canvas.TextWidth(out_str)) div 2,6,out_str);

                Canvas.font.Color:=clSilver;
                Canvas.TextOut(t_w-font_h*2-3,5,'_');
                Canvas.TextOut(t_w-font_h-3,7,'х');
                canvas.Font.Bold:=false;
              end;
            3: begin  {openbox }
                 //window's decorations
                 Canvas.Pen.Style:=psSolid;
                 Canvas.Pen.Color:=Profile_perf.font_cl;
                 //borders
                 Canvas.Brush.Color:=Profile_perf.back_cl;                 //FIX!!!
                 Canvas.Rectangle(0,font_h,t_w,font_h*lines_ct);

                 //widows's text
                 Canvas.font.Color:=Profile_perf.cmd_cl;
                 Canvas.TextOut(2,font_h * 2 ,out_str);

                 //title testing
                 canvas.Brush.color:=Profile_perf.font_cl;
                 canvas.RoundRect(0,0,t_w,font_h+(shadow_size div 2),shadow_size,shadow_size);
                 canvas.Rectangle(0,font_h-shadow_size,t_w,font_h+(shadow_size div 2));


                 out_str:='Ввод данных';
                 Canvas.font.Color:=Profile_perf.back_cl;
                 canvas.Font.Bold:=true;
                 Canvas.TextOut((t_w-canvas.TextWidth(out_str)) div 2,1,out_str);

                 Canvas.font.Color:=clSilver;
                 Canvas.TextOut(t_w-font_h*2,-3,'_');
                 Canvas.TextOut(t_w-font_h,0,'х');
                 canvas.Font.Bold:=false;

                 Canvas.Pen.Color:=Profile_perf.back_cl;
               end;
       end;


       //input area
       Canvas.font.color:=Profile_perf.font_cl;
       Canvas.Brush.Color:=Profile_perf.back_cl;
       Canvas.Pen.Color:=Profile_perf.font_cl;
       input_width:= canvas.TextWidth('0000-32768');
       inp_x:=(t_w - input_width) div 2;
       Canvas.line(inp_x,font_h*5-2,inp_x+input_width,font_h*5-2);
       {GOOD BYE ;) }
  end;
end;

procedure xterm_readln;  //вывод окна и запрос данных... testing
var
  key:char;
begin
 { ............

 код перемещен в  create_DialogFrame
   ............
 }
  {clean input area}

  with term do
  begin
       readln_proc_lock:=query;
       scroll.Enabled:=false;

       {clean input area}
       key:=#0; term.FormKeyPress(term, key);
      // repaint; //deprecated
  end;
end;

procedure xterm_writeln(message:string);  //пересмотр
begin
  with term do begin
    AddData_toStrList(message);

    //отрисовать...
  redraw(false);
  OptiRepaint;   //EXPEREMENTAL
  end;
end;

begin
    ini_DEC;
end.

