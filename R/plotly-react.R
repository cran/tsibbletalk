globalVariables(".GROUP")

clean_plotly_attrs <- function(x) {
  if (!is_formula(x)) return(NULL)
  nm <- f_name(x)
  gsub("^~", "", nm)
}

is_faceted <- function(layout) {
  sum(grepl("axis", names(layout))) > 2
}

facet_by <- function(data, plotly_data) {
  nfacets <- vec_size(plotly_data)
  key <- vec_rep_each(
    seq_len(nfacets),
    # NA identifies the grouping info
    map_int(plotly_data, function(z) sum(!is.na(z$x))))
  vec_split(as_tibble(data), key)$val
}

is_aes_mapping_present <- function(plotly) {
  !is_null(plotly$x$attrs[[1]]$colour)
}

plotlyReactData <- function(p, data) {
  UseMethod("plotlyReactData")
}

plotlyReactData.plotly <- function(p, data) {
  if (is_aes_mapping_present(p)) {
    colour_chr <- clean_plotly_attrs(p$x$attrs[[1]]$colour)
    data <- vec_slice(data, vec_order(data[[colour_chr]]))
  }
  data_lst <- list(data)
  if (is_aes_mapping_present(p) || is_faceted(p$x$layout)) {
    data_lst <- facet_by(data, p$x$data)
  }
  data_lst
}

colour_var <- function(p) {
  out <- p$mapping$colour %||%
    vec_unique(map_chr(p$layers, function(x) as_name(x$mapping$colour)))
  if (is.null(out)) {
    character()
  } else {
    as_name(out)
  }
}

facet_vars <- function(p) {
  p$facet$vars()
}

plotlyReactData.gg <- function(p, data) {
  colour_loc <- vec_group_loc(data[colour_var(p)])$loc
  data_lst <- map(colour_loc, function(x) vec_slice(data, x))
  fct_vars <- facet_vars(p)
  facet_loc <- map(data_lst, function(x) vec_group_loc(x[fct_vars])$loc)
  out <- vec_init_along(data_lst)
  for (i in seq_along(data_lst)) {
    fct_i <- facet_loc[[i]]
    out[[i]] <- vec_init_along(fct_i)
    for (j in seq_along(fct_i)) {
      out[[i]][[j]] <- vec_slice(data_lst[[i]], fct_i[[j]])
    }
  }
  vec_c(!!!out)
}

#' @importFrom plotly plotly_data
#' @importFrom dplyr group_by
finalise_data <- function(p, data) {
  x_chr <- clean_plotly_attrs(p$x$attrs[[1]]$x)
  y_chr <- clean_plotly_attrs(p$x$attrs[[1]]$y)
  grps <- group_vars(group_by(plotly_data(p), ".GROUP" := 1L))
  data_lst <- map(data, function(x) plotly::group2NA(x, grps))
  if (!is_aes_mapping_present(p)) {
    map2(
      data_lst,
      p$x$data,
      function(x, y) list2(
        x = x[[x_chr]], y = x[[y_chr]], 
        text = parse_tooltip(
          !!x_chr := paste(x[[x_chr]], x[[grps]], sep = " @ "),
          !!y_chr := x[[y_chr]]),
        !!!y[-(1:3)])
    )
  } else {
    col_chr <- clean_plotly_attrs(p$x$attrs[[1]]$colour)
    map2(
      data_lst,
      p$x$data,
      function(x, y) list2(
        x = x[[x_chr]], y = x[[y_chr]], 
        text = parse_tooltip(
          !!x_chr := paste(x[[x_chr]], x[[grps]], sep = " @ "),
          !!y_chr := x[[y_chr]],
          !!col_chr := x[[col_chr]]),
        !!!y[-(1:3)])
    )
  }
}

parse_tooltip <- function(...) {
  tbl <- new_data_frame(list2(...))
  paste_text(tbl)
}

paste_text <- function(data) {
  nm <- names(data)
  msg <- map(seq_along(nm), function(x) 
    paste(nm[x], curly_braces(nm[x]), sep = ": "))
  as.character(eval_tidy(quo(
    glue_data(!!data, !!!msg, .sep = "<br />", .envir = !!caller_env())
  )))
}

plotlyReact <- function(outputId, data, plotly, clear = FALSE,
                        session = shiny::getDefaultReactiveDomain()) {
  new_data <- plotlyReactData(plotly, data)
  plotly <- plotly::plotly_build(plotly)
  plotly::plotlyProxyInvoke(
    plotly::plotlyProxy(outputId, session),
    "react",
    finalise_data(plotly, new_data),
    reset_x_range(plotly$x$layout, clear = clear),
    plotly$x$config
  )
}

reset_x_range <- function(layout, clear = FALSE) {
  # TODO: x as linear type but should be contextual ticktext
  xaxis <- names(layout)[grepl("xaxis", names(layout))]
  for (i in xaxis) {
    if (clear) {
      layout[[i]]$tickvals <- numeric()
      layout[[i]]$ticktext <- character()
    } else {
      layout[[i]]$tickvals <- layout[[i]]$ticktext <- NULL
    }
    layout[[i]]$autorange <- TRUE # ggplotly panel spacing gone
  }
  layout
}

group_vars <- function(x) {
  if (!inherits(x, "grouped_df")) return(character())
  head(names(attr(x, "groups")), -1)
}

is_ggplot <- function(x) {
  inherits(x, "ggplot")
}
