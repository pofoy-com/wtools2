<?php

class Captcha {
    // 宽度
    private $width;
    // 高度
    private $height;
    // 字符长度
    private $length;
    // 图片资源
    private $image;
    // 字体文件
    private $webfont;
    /**
     * 验证码字符
     * @var string
     */
    private $code;
    /**
     * 构造方法
     *
     * @param integer $width
     * @param integer $height
     * @param integer $length
     */
    public function __construct($width=80, $height=30, $length=4){
        if(session_status() < 2 ){
            session_start();
        }
        $this->webfont = dirname(__FILE__). '/webfont.ttf';
        $this->width = $width;
        $this->height= $height;
        $this->length= $length;
        $this->code  = $this->str_generator();
    }
    /**
     * 生成验证码
     * @return void
     */
    public function image2(){
        // 创建画布
        $this->set_canvas();
        // 设置线
        $this->set_line();
        // 设置杂点
        $this->set_dots();
        // 设置字符
        $this->set_code();
        // 保存到SESSION
        $_SESSION['captcha'] = strtolower($this->code);
        // 生成图片
        header('content-type: image/jpeg');
        imagejpeg($this->image);
    }
    /**
     * 生成验证码字符
     *
     * @return void
     */
    private function str_generator(){
        $text = mt_rand(10000, 99999);
        $text = md5($text) . 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0';
        $text = str_shuffle($text);
        return substr($text, 0, $this->length);
    }
    /**
     * 创建画面
     *
     * @return void
     */
    private function set_canvas($min=180, $max=255){
        $this->image = imagecreate($this->width, $this->height);
        $this->random_color_rgb($min, $max);
    }
    /**
     * 添加字符到画布
     * @param integer $min
     * @param integer $max
     * @return void
     */
    private function set_code($min=0, $max=120){
     
        for ($i=0; $i < $this->length; $i++) { 
            // 
            $color = $this->random_color_rgb($min,$max); 
            $font_init  = (int)$this->height / 3;
            $font_size  = mt_rand($font_init, $font_init*2);
            $font_height= imagefontheight($font_size);
            $t = mt_rand(-20, 20);
            $y = mt_rand($font_height, $this->height);
            $x = ($this->width / $this->length) * $i +2;
            imagettftext($this->image, $font_size, $t, $x, $y, $color, $this->webfont, $this->code[$i]);
        }
    }

    private function set_line($min=80, $max=180){
        for ($i=0; $i < $this->length; $i++) { 
           $color = $this->random_color_rgb($min, $max);
           $x1 = mt_rand(0, $this->width/$this->length);
           $y1 = mt_rand(0, $this->height);
           $x2 = mt_rand($this->width - $this->width / $this->length, $this->width);
           $y2 = mt_rand(0, $this->height);
           imageline($this->image, $x1, $y1, $x2, $y2, $color);
        }
    }

    private function set_dots($min=40, $max=130){
        $color = $this->random_color_rgb($min, $max);
        for ($i=0; $i < 300; $i++) { 
            imagesetpixel($this->image, rand(0, $this->width), rand(0,$this->height), $color);
        }
    }
    
    /**
     * 生成随机颜色
     * @param integer $min
     * @param integer $max
     * @return int
     */
    private function random_color_rgb($min=0, $max=255){
        list($r, $g, $b) = [mt_rand($min, $max), mt_rand($min, $max), mt_rand($min, $max)];
        return imagecolorallocate($this->image, $r, $g, $b);
    }
    /**
     * 销毁
     */
    public function __destruct() {
        imagedestroy($this->image);
    }
}

$captcha = new Captcha();
$captcha->image2();