# Claude masaüstü (Code sekmesi) ile özellik eşliği

**Tarih:** 2026-10-22 · Kaynak: Claude masaüstü uygulamasının Code sekmesinde görünen özellikler (bu oturumdaki uygulama
ve Twitter'daki "Portals" ekran görüntüsü). Claude uygulamasının iç davranışı okunmadı; sütun "gözlenen davranış"tır.

Durum: ✅ var · 🟡 kısmen · ❌ yok. Öncelik: **P1** sonraki milestone, **P2** v1.1, **P3** sonra.

## Metrikler (doğruluk)
| Özellik | Claude uygulaması | Monster | Not |
|---|---|---|---|
| Bağlam doluluğu % (gönder düğmesi yanında) | ✅ | ✅ 2026-10-22 | Başlıkta yüzde; pencere bilinmiyorsa token sayısı (uydurma % yok) |
| 5 saatlik / haftalık plan limiti kutuları | ✅ | ✅ 2026-10-22 | `rate_limit_event.unifiedWindows`, sıfırlanma saati ile |
| Maliyet | abonelikte $ gösterilmez | ✅ "API karşılığı" | Kümülatif `total_cost_usd` artık iki kez sayılmıyor; liste fiyatı tahmini olarak etiketli |
| Bağlam penceresi | model başına | ✅ | Alt ajan modelinin penceresi artık seçilmiyor |
| Otomatik sıkıştırma (autocompact) durumu | ✅ | ❌ **P1** | `autocompact_state` olayı şu an yok sayılıyor |

## Session yönetimi
| Özellik | Claude | Monster | Öncelik |
|---|---|---|---|
| Projeye göre gruplu liste, arama, çalışıyor göstergesi | ✅ | ✅ | — |
| Yeniden adlandır / sabitle / arşivle / sil | ✅ | 🟡 sil | **P1** |
| Session'ı çatallama (fork) | ✅ | ❌ | P2 |
| Geri sar / checkpoint | ✅ | ❌ | P2 |
| Bitince / izin isteyince macOS bildirimi | ✅ | ❌ | **P1** |
| Paralel / yan session'lar | ✅ | ❌ | P3 |

## Composer
| Özellik | Claude | Monster | Öncelik |
|---|---|---|---|
| Model / effort / izin modu seçicileri | ✅ | ✅ | — |
| Slash komutları + otomatik tamamlama (`/compact`, `/clear`, skill'ler) | ✅ | ✅ 2026-10-22 | Liste CLI `initialize` cevabından; ↑/↓, ⇥/↩, Esc |
| `@dosya` bahsetme ve otomatik tamamlama | ✅ | ✅ 2026-10-22 | Kod modunda; içerik Monster tarafından eklenir (CLI stream-json'da açmıyor) |
| Görsel / dosya ekleme (sürükle-bırak, yapıştır) | ✅ | ✅ 2026-10-22 | Yapıştırma doğrulandı; sürükle-bırak ve ataş seçici uygulamada denenmedi |
| Son mesajı düzenle / yeniden dene | ✅ | ❌ | P2 |

## Transcript
| Özellik | Claude | Monster | Öncelik |
|---|---|---|---|
| Akış, düşünme bloğu, araç kartları, diff | ✅ | ✅ | — |
| Görev listesi (TodoWrite) sabit paneli | ✅ | ❌ | **P1** |
| Alt ajan transcript'leri iç içe | ✅ | 🟡 sayaç | P2 |
| Sohbet içi SVG/HTML widget | ✅ | ✅ | — |
| Transcript içinde arama | ❓ | ❌ | P3 |
| Mesaj kopyalama | ✅ | 🟡 kod bloğu | P2 |

## Paneller
| Özellik | Claude | Monster | Öncelik |
|---|---|---|---|
| Değişiklikler (diff) paneli | ✅ | ❌ | P2 |
| Terminal paneli | ✅ | ❌ | P3 |
| Tarayıcı / önizleme paneli | ✅ | ❌ | P3 (BACKLOG) |
| PR / CI durumu, worktree / branch | ✅ | ❌ | P3 |
| MCP sunucu durumu | ✅ | ❌ | P3 (BACKLOG) |

## Bilinen metrik dışı bulgular
- Monster sohbetlerinde her tur ~551k token'lık istem gidiyor: CLI kullanıcının tüm global kurallarını, MCP sunucularını ve
  skill'lerini yüklüyor. Sohbet modunda `--strict-mcp-config` / ayrı bir ayar dizini ile hafif başlatma değerlendirilmeli (P1, doğrulanmadı).
