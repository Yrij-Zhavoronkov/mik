unit setup;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs, ComCtrls,
  ExtCtrls, Menus, Buttons, StdCtrls, ColorBox, types;

type

  { Tparam }

  Tparam = class(TForm)
    Bevel1: TBevel;
    back_color: TColorButton;
    font_color: TColorButton;
    kegel_size: TComboBox;
    GroupBox1: TGroupBox;
    GroupBox2: TGroupBox;
    kegel_name: TComboBox;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    Label6: TLabel;
    Label7: TLabel;
    Label8: TLabel;
    Label9: TLabel;
    MainMenu1: TMainMenu;
    MenuItem1: TMenuItem;
    MenuItem2: TMenuItem;
    MenuItem3: TMenuItem;
    MenuItem4: TMenuItem;
    MenuItem5: TMenuItem;
    PageControl1: TPageControl;
    x_term_prm: TPanel;
    SB: TSpeedButton;
    SI: TSpeedButton;
    TabSheet1: TTabSheet;
    TabSheet2: TTabSheet;
    TabSheet3: TTabSheet;
    TabSheet4: TTabSheet;
    procedure back_colorColorChanged(Sender: TObject);
    procedure font_colorColorChanged(Sender: TObject);
    procedure kegel_nameChange(Sender: TObject);
    procedure kegel_sizeChange(Sender: TObject);
    procedure x_term_prmClick(Sender: TObject);
    procedure SBClick(Sender: TObject);
  private
    { private declarations }
  public
    { public declarations }
  end;

var
  param: Tparam;

implementation

uses
  eterm;

{$R *.lfm}
//должно настраиваться цвет шрифта команд памяти
//формат команд...
//М/Б цвета логов
//М/Б цветаассемблера
//цвет фона консоли шрифт/цвет консоли ..


{ Tparam }

procedure Tparam.SBClick(Sender: TObject);
begin
  x_term_prm.Font.Bold:=SB.Down;
  x_term_prm.Font.Italic:=SI.Down;
end;

procedure Tparam.kegel_sizeChange(Sender: TObject);
begin
  x_term_prm.Font.Size:=strtoint(kegel_size.Text);
end;

procedure Tparam.x_term_prmClick(Sender: TObject);
begin
  //
  term.frame.Canvas.Font:=x_term_prm.Font;
  term.frame.Canvas.Brush.Color:=x_term_prm.Color;
  term.frame.Canvas.Pen.Color:=term.frame.Canvas.Font.Color;
end;

procedure Tparam.kegel_nameChange(Sender: TObject);
begin
  x_term_prm.Font.Name:=kegel_name.Text;
end;

procedure Tparam.font_colorColorChanged(Sender: TObject);
begin
 x_term_prm.Font.Color:=font_color.ButtonColor;
end;

procedure Tparam.back_colorColorChanged(Sender: TObject);
begin
  x_term_prm.Color:=back_color.ButtonColor;
end;

end.

