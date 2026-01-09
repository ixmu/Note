// ==UserScript==
// @name         (新)贵州省党员干部网络学院秒看视频、自动提交等。
// @namespace    zzy
// @version      1.7
// @description  贵州省党员干部网络学院秒看视频
// @author       zzy
// @match        *https://gzwy.gov.cn/dsfa/nc/pc/course/views/course*
// @icon         https://gzwy.gov.cn/dsfa/gzgb.ico
// @grant        none
// @license MIT
// ==/UserScript==
 
(function () {
  //'use strict';
 
 
  window.onload = function () {
    var stop = false;
    var $div = $(`
      <div style="z-index:10022;position:fixed;top:50px;right:20px;padding:10px;background:aliceblue">
      <div class="jsdiv" id="jsdiv1" style="padding:5px;">
        <span>开始</span>
      </div>
      <div class="jsdiv" id="jsdiv2" style="margin-top:10px;padding:5px;">
        <span>停止</span>
      </div>
      </div>
      <div style="z-index:10022;position:fixed;top:150px;right:0px;padding:0px;">
        <span>有问题请反馈</span>
      </div>
    `);
 
    var $style = `
      <style type="text/css">
      .jsdiv:{
        background: aqua;
      }
      .jsdiv:hover{
        background:#fff;
        cursor: pointer;
      }
      </style>
    `
    $('body').append($div);
    $('head').append($style);
    var jsdiv1 = document.getElementById("jsdiv1");
    var jsdiv2 = document.getElementById("jsdiv2");
    jsdiv1.addEventListener("click", function () {
      $("div[data-title='点击静音']")[0].click();
      $("div[data-title=点击播放]")[0].click();
      window.onblur = function () {
 
      }
      stop = false;
      subJd();
    })
    jsdiv2.addEventListener("click", function () {
      stop = true;
    })
    function getSec(t) {
      if (!t) {
        t = "00:00:00";
      }
      t = t.split(":");
      var s = t[0] * 60 * 60 + t[1] * 60 + t[2] * 1;
      return s;
    }
    function subJd() {
      if (stop) {
        return;
      }
      var info = JSON.parse($(".selConListItem")[0].getAttribute("data-item"));
      var sourceUrl = dsf.url.getWebPath("nc/xxgl/xxjl/addXxjlByKczj");
      var params = {
        // nc_students_id: userId,
        relid: info.kjid,
        bigtimespan: info.kjsc,
        timespan: info.kjsc,
        dwid:info.kcid,
        //当前课程已经播放的时间,
        pass: "1",
        sumtime: getSec(info.kjsc),
        everytime: 10,
        playRate: 1,
      };
      if (dsf.url.queryString("ztbid")) {
        params.zybId = dsf.url.queryString("ztbid");
      }
      dsf.http
        .request(sourceUrl, params, "POST")
        .done(function (res) {
          if (res.success) {
            console.log(res.kjjd);
            if (JSON.stringify(res.data) !== "{}") {
              dsf.layer.message(res.message, true);
            }
            if (true) {
              var name = $(".selConListItem canvas")[0].getAttribute("id");
              var p = res.kjjd ? Number(res.kjjd) : 0;
              if (p > 100) {
                p = 100;
              }
              $("#" + name).attr("data-percent", p);
              $("#" + name).circleProgress({
                obj: name,
                innerColor: "#D40000",
                size: 40,
                radius: 16,
                textY: 24,
                textX: 12,
              });
              dsf.layer.message("提交成功，进度" + p + "%!");
              if (p < 100) {
                subJd();
              } else {
                if (window.ctime) {
                  // 提交频率
                  if ((new Date().getTime() - window.ctime.getTime()) < 30000) {
 
                    console.log("时间未到");
                    subJd();
                  } else {
                    window.ctime = new Date();
                    if ($(".com-canvas[data-percent!='100']").length) {
 
                      $(".com-canvas[data-percent!='100']")[0].click();
                      subJd();
                    } else {
                      dsf.layer.alert("脚本提交全部课程！", function () {
                        var index = layer.alert();
                        layer.close(index);
                      });
                    }
                  }
                } else {
                  window.ctime = new Date();
                  if ($(".com-canvas[data-percent!='100']").length) {
 
                    $(".com-canvas[data-percent!='100']")[0].click();
                    subJd();
                  } else {
                    dsf.layer.alert("脚本提交全部课程！", function () {
                      var index = layer.alert();
                      layer.close(index);
                    });
                  }
 
                }
              }
            }
          } else if (res.state == "61000") {
            dsf.layer.alert(res.message, function () {
              var path = dsf.url.getWebPath("/nc/pc/main/views/main.html");
              window.location.href = path;
            });
          } else {
            dsf.layer.message(res.message, false);
          }
        })
        .error(function (err) {
          dsf.layer.message("学时记录异常,请联系管理员", false);
        })
        .always(function () { })
        .exec();
    }
 
  }
})();